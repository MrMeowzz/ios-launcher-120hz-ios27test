#import "../components/LogUtils.h"
#include "src/Utils.h"
#include "src/LCUtils/Shared.h"
#include <string.h>
#import "LCUtils.h"
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <libgen.h>
#import <mach-o/dyld.h>
#import <mach-o/fat.h>
#include <mach-o/ldsyms.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <sys/mman.h>
#import <sys/stat.h>
// #import <Foundation/Foundation.h>
// #import <mach-o/dyld.h>
// #import <mach-o/loader.h>
#include <errno.h>
#import <libkern/OSByteOrder.h>
#import <mach/machine.h>

static void insertRPathCommand(const char* path, struct mach_header_64* header);

static uint32_t rnd32(uint32_t v, uint32_t r) {
	r--;
	return (v + r) & ~r;
}

static void insertDylibCommand(uint32_t cmd, const char* path, struct mach_header_64* header) {
	const char* name = cmd == LC_ID_DYLIB ? basename((char*)path) : path;
	struct dylib_command* dylib = (struct dylib_command*)(sizeof(struct mach_header_64) + (void*)header + header->sizeofcmds);
	dylib->cmd = cmd;
	dylib->cmdsize = sizeof(struct dylib_command) + rnd32((uint32_t)strlen(name) + 1, 8);
	dylib->dylib.name.offset = sizeof(struct dylib_command);
	dylib->dylib.compatibility_version = 0x10000;
	dylib->dylib.current_version = 0x10000;
	dylib->dylib.timestamp = 2;
	strncpy((void*)dylib + dylib->dylib.name.offset, name, strlen(name));
	header->ncmds++;
	header->sizeofcmds += dylib->cmdsize;
}

static BOOL isDylibPathCommand(uint32_t cmd) {
	return cmd == LC_ID_DYLIB || cmd == LC_LOAD_DYLIB || cmd == LC_LOAD_WEAK_DYLIB || cmd == LC_REEXPORT_DYLIB || cmd == LC_LOAD_UPWARD_DYLIB;
}

static BOOL replaceDylibPath(struct mach_header_64* header, const char* oldPath, const char* newPath) {
	uint8_t* imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
	struct load_command* command = (struct load_command*)imageHeaderPtr;
	for (uint32_t i = 0; i < header->ncmds; i++) {
		if (isDylibPathCommand(command->cmd)) {
			struct dylib_command* dylib = (struct dylib_command*)command;
			char* dylibName = (char*)dylib + dylib->dylib.name.offset;
			if (strcmp(dylibName, oldPath) == 0) {
				uint32_t newNameLen = (uint32_t)strlen(newPath) + 1;
				uint32_t newCmdSize = sizeof(struct dylib_command) + rnd32(newNameLen, 8);
				int32_t sizeDiff = (int32_t)newCmdSize - (int32_t)dylib->cmdsize;

				if (sizeDiff != 0) {
					uint8_t* nextCmd = (uint8_t*)command + dylib->cmdsize;
					uint8_t* endOfCmds = imageHeaderPtr + header->sizeofcmds;
					size_t remainingSize = endOfCmds - nextCmd;
					if (remainingSize > 0) {
						memmove(nextCmd + sizeDiff, nextCmd, remainingSize);
					}
					header->sizeofcmds += sizeDiff;
				}

				memset((uint8_t*)dylib + sizeof(struct dylib_command), 0, newCmdSize - sizeof(struct dylib_command));
				dylib->cmdsize = newCmdSize;
				dylib->dylib.name.offset = sizeof(struct dylib_command);
				strcpy((char*)dylib + dylib->dylib.name.offset, newPath);
				return YES;
			}
		}
		command = (struct load_command*)((uint8_t*)command + command->cmdsize);
	}
	return NO;
}

static BOOL hasRPathCommand(struct mach_header_64* header, const char* path) {
	uint8_t* imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
	struct load_command* command = (struct load_command*)imageHeaderPtr;
	for (uint32_t i = 0; i < header->ncmds; i++) {
		if (command->cmd == LC_RPATH) {
			struct rpath_command* rpath = (struct rpath_command*)command;
			char* rpathName = (char*)rpath + rpath->path.offset;
			if (strcmp(rpathName, path) == 0) {
				return YES;
			}
		}
		command = (struct load_command*)((uint8_t*)command + command->cmdsize);
	}
	return NO;
}

static BOOL ensureRPathCommand(const char* path, struct mach_header_64* header) {
	if (hasRPathCommand(header, path)) {
		return NO;
	}
	insertRPathCommand(path, header);
	return YES;
}

void noopOverwrite(struct load_command* command) {
	uint32_t old_size = command->cmdsize;
	memset(command, 0, old_size);
	command->cmd = 0x12345678; // dont question it lol, apple will most likely not have a command with this so itll just ignore it... hopefully
	command->cmdsize = old_size;
}

static void insertRPathCommand(const char* path, struct mach_header_64* header) {
	struct rpath_command* rpath = (struct rpath_command*)(sizeof(struct mach_header_64) + (void*)header + header->sizeofcmds);
	rpath->cmd = LC_RPATH;
	rpath->cmdsize = rnd32(sizeof(struct rpath_command) + (uint32_t)strlen(path) + 1, 8);
	// rpath->cmdsize = sizeof(struct rpath_command) + rnd32((uint32_t)strlen(path) + 1, 8);
	rpath->path.offset = sizeof(struct rpath_command);
	// strncpy((void*)rpath + rpath->path.offset, path, strlen(path));
	memcpy((void*)rpath + rpath->path.offset, path, strlen(path));
	((char*)rpath)[rpath->cmdsize - 1] = '\0';
	header->ncmds++;
	header->sizeofcmds += rpath->cmdsize;
}

void LCPatchAddRPath(const char* path, struct mach_header_64* header) {
	insertRPathCommand("@executable_path/../../Tweaks", header);
	insertRPathCommand("@loader_path", header);
}

BOOL isBinarySigned(struct mach_header_64* header) {
    uint8_t* ptr = (uint8_t*)header + sizeof(struct mach_header_64);
    struct load_command* cmd = (struct load_command*)ptr;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (cmd->cmd == LC_CODE_SIGNATURE) {
            return YES;
        }
        cmd = (struct load_command*)((uint8_t*)cmd + cmd->cmdsize);
    }
    return NO;
}


// TODO: look at https://github.com/LiveContainer/LiveContainer/blob/main/LiveContainer/LCMachOUtils.m and see if i can really manipulate with codesigs

// static void invalidateCodeSignature(struct mach_header_64* header) {
//     uint8_t* imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
//     struct load_command* command = (struct load_command*)imageHeaderPtr;
//
//     for (uint32_t i = 0; i < header->ncmds; i++) {
//         if (command->cmd == LC_CODE_SIGNATURE) {
//             // Option 1: Change the command to a harmless one
//             command->cmd = LC_LOADFVMLIB; // Obsolete, ignored command
//
//             // Option 2: Or zero out the linkedit_data_command
//             // struct linkedit_data_command* sig = (struct linkedit_data_command*)command;
//             // sig->dataoff = 0;
//             // sig->datasize = 0;
//
//             break;
//         }
//         command = (struct load_command*)((uint8_t*)command + command->cmdsize);
//     }
// }

// Error Codes
// 0 = Success
// -1 = Binary is signed, cant manipulate
int LCPatchExecSlice(const char* path, struct mach_header_64* header, bool withGeode, bool withANGLE) {
	uint8_t* imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);

	// Literally convert an executable to a dylib for normal launcher mode, or restore it
	// to an executable when Geode is injected through EnterpriseLoader.
	if (header->magic == MH_MAGIC_64) {
		if (withGeode) {
			header->filetype = MH_EXECUTE;
			header->flags |= MH_PIE;
			header->flags &= ~MH_NO_REEXPORTED_DYLIBS;
		} else {
			header->filetype = MH_DYLIB;
			header->flags |= MH_NO_REEXPORTED_DYLIBS;
			header->flags &= ~MH_PIE;
		}
	}

	// Patch __PAGEZERO to map just a single zero page, fixing "out of address space".
	struct segment_command_64* seg = (struct segment_command_64*)imageHeaderPtr;
	assert(seg->cmd == LC_SEGMENT_64 || seg->cmd == LC_ID_DYLIB);
	if (seg->cmd == LC_SEGMENT_64 && seg->vmaddr == 0) {
		assert(seg->vmsize == 0x100000000);
		seg->vmaddr = 0x100000000 - 0x4000;
		seg->vmsize = 0x4000;
	} else if (withGeode) {
		seg->vmaddr = 0x0;
		seg->vmsize = 0x100000000;
	}

	BOOL hasDylibCommand = NO;
	BOOL hasLoaderCommand = NO;
	BOOL hasOpenGLESCommand = NO;
	BOOL hasANGLECommand = NO;
	const char* tweakLoaderPath = "@loader_path/../../Tweaks/TweakLoader.dylib";
	const char* geodeLoaderPath = "@executable_path/EnterpriseLoader.dylib";
	const char* openGlesLoadCmd = "/System/Library/Frameworks/OpenGLES.framework/OpenGLES";
	const char* ANGLELoadCmd = "@executable_path/Frameworks/ANGLEGLKit.framework/ANGLEGLKit";
	struct load_command* command = (struct load_command*)imageHeaderPtr;
	struct load_command* lcIDcmd = NULL;
	struct dylib_command* lcLOADcmd = NULL;

	if (NSClassFromString(@"LCSharedUtils")) {
		NSURL* bundlePath = [[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName]];
		NSString* frameworks = [bundlePath URLByAppendingPathComponent:@"Frameworks"].path;
		AppLog(@"Detected LiveContainer! ANGLE should resolve from GD Frameworks: %@", frameworks);
	}

	for (int i = 0; i < header->ncmds; i++) {
		if (command->cmd == LC_ID_DYLIB) {
			lcIDcmd = command;
			hasDylibCommand = YES;
		} else if (command->cmd == LC_LOAD_DYLIB) {
			struct dylib_command* dylib = (struct dylib_command*)command;
			char* dylibName = (char*)dylib + dylib->dylib.name.offset;
			if (strcmp(dylibName, tweakLoaderPath) == 0) {
				lcLOADcmd = dylib;
				hasLoaderCommand = YES;
			}
			if (strcmp(dylibName, openGlesLoadCmd) == 0) {
				hasOpenGLESCommand = YES;
			}
			if (strcmp(dylibName, ANGLELoadCmd) == 0) {
				hasANGLECommand = YES;
			}
		}
		command = (struct load_command*)((void*)command + command->cmdsize);
	}

	if (withGeode) {
		if (hasDylibCommand && hasLoaderCommand) {
			uint32_t totalSpace = lcIDcmd->cmdsize + lcLOADcmd->cmdsize;
			uint32_t newCmdSize = sizeof(struct dylib_command) + rnd32((uint32_t)strlen(geodeLoaderPath) + 1, 8);
			if (newCmdSize <= totalSpace) {
				memset(lcIDcmd, 0, totalSpace);
				struct dylib_command* newCmd = (struct dylib_command*)lcIDcmd;
				newCmd->cmd = LC_LOAD_DYLIB;
				newCmd->cmdsize = newCmdSize;
				newCmd->dylib.name.offset = sizeof(struct dylib_command);
				newCmd->dylib.compatibility_version = 0x10000;
				newCmd->dylib.current_version = 0x10000;
				newCmd->dylib.timestamp = 2;
				strncpy((void*)newCmd + newCmd->dylib.name.offset, geodeLoaderPath, strlen(geodeLoaderPath));

				if (totalSpace > newCmdSize) {
					struct load_command* padding = (struct load_command*)((uint8_t*)newCmd + newCmdSize);
					padding->cmd = 0;
					padding->cmdsize = totalSpace - newCmdSize;
				}
				header->ncmds--;
			} else {
				noopOverwrite(lcIDcmd);
				noopOverwrite((struct load_command*)lcLOADcmd);
				insertDylibCommand(LC_LOAD_DYLIB, geodeLoaderPath, header);
				header->ncmds -= 2;
			}
		}
	} else {
		if (!hasDylibCommand) {
			insertDylibCommand(LC_ID_DYLIB, path, header);
		}
		if (!hasLoaderCommand) {
			insertDylibCommand(LC_LOAD_DYLIB, tweakLoaderPath, header);
		}
	}

	if (withANGLE) {
		if (hasOpenGLESCommand && !hasANGLECommand) {
			if (replaceDylibPath(header, openGlesLoadCmd, ANGLELoadCmd)) {
				AppLog(@"Patched Geometry Dash executable to use ANGLEGLKit.");
			}
		}
	} else {
		if (hasANGLECommand) {
			if (replaceDylibPath(header, ANGLELoadCmd, openGlesLoadCmd)) {
				AppLog(@"Restored Geometry Dash executable to use OpenGLES.");
			}
		}
	}

	return 0;
}

BOOL LCPatchANGLEFrameworkSlice(const char* path, struct mach_header_64* header) {
	AppLog(@"Patching ANGLEGLKit framework dependencies: %@", [NSString stringWithUTF8String:path]);
	BOOL patched = NO;

	// The public ANGLEGLKit build depends on @rpath/libEGL and @rpath/libGLESv2.
	// In LiveContainer, @executable_path can point at the LC host instead of GD, so
	// lazy EGL symbols can resolve to 0x0 and crash at startup. Use @loader_path so
	// ANGLEGLKit always finds its sibling frameworks inside GD.app/Frameworks.
	patched |= replaceDylibPath(header, "@rpath/libEGL.framework/libEGL", "@loader_path/../libEGL.framework/libEGL");
	patched |= replaceDylibPath(header, "@rpath/libGLESv2.framework/libGLESv2", "@loader_path/../libGLESv2.framework/libGLESv2");

	// Make the install name sane too. This is mostly for tools/debugging, but it
	// also helps dyld avoid stale /Library/Frameworks identities.
	patched |= replaceDylibPath(header, "/Library/Frameworks/ANGLEGLKit.framework/ANGLEGLKit", "@rpath/ANGLEGLKit.framework/ANGLEGLKit");

	if (ensureRPathCommand("@loader_path/..", header)) {
		patched = YES;
		AppLog(@"Added ANGLEGLKit rpath @loader_path/..");
	}
	if (ensureRPathCommand("@executable_path/Frameworks", header)) {
		patched = YES;
		AppLog(@"Added ANGLEGLKit rpath @executable_path/Frameworks");
	}

	AppLog(@"ANGLEGLKit dependency patch result: %@", patched ? @"patched" : @"already patched");
	return patched;
}

BOOL LCPatchLibWithANGLE(const char* path, struct mach_header_64* header, bool withANGLE) {
	AppLog(@"Patching %@ with ANGLE? %@", [NSString stringWithUTF8String:path], withANGLE ? @"YES" : @"NO");

	// Do not refuse signed dylibs here. Rewriting the load command invalidates the
	// old signature anyway, and the launcher signs the patched files afterwards.
	if (isBinarySigned(header)) {
		AppLog(@"Library has a code signature; patching anyway and expecting it to be re-signed.");
	}

	uint8_t* imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
	if (header->magic == MH_MAGIC_64) {
		header->filetype = MH_DYLIB;
		header->flags &= ~MH_PIE;
	}

	BOOL hasOpenGLESCommand = NO;
	BOOL hasANGLECommand = NO;
	struct load_command* command = (struct load_command*)imageHeaderPtr;

	const char* openGlesLoadCmd = "/System/Library/Frameworks/OpenGLES.framework/OpenGLES";
	const char* ANGLELoadCmd = "@executable_path/Frameworks/ANGLEGLKit.framework/ANGLEGLKit";

	if (NSClassFromString(@"LCSharedUtils")) {
		NSURL* bundlePath = [[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName]];
		NSString* frameworks = [bundlePath URLByAppendingPathComponent:@"Frameworks"].path;
		AppLog(@"Detected LiveContainer! ANGLE should resolve from GD Frameworks: %@", frameworks);
	}

	for (int i = 0; i < header->ncmds; i++) {
		if (command->cmd == LC_LOAD_DYLIB) {
			struct dylib_command* dylib = (struct dylib_command*)command;
			char* dylibName = (char*)dylib + dylib->dylib.name.offset;
			if (strcmp(dylibName, openGlesLoadCmd) == 0) {
				hasOpenGLESCommand = YES;
			}
			if (strcmp(dylibName, ANGLELoadCmd) == 0) {
				hasANGLECommand = YES;
			}
		}
		command = (struct load_command*)((void*)command + command->cmdsize);
	}

	if (!hasOpenGLESCommand && !hasANGLECommand) {
		return NO;
	}

	if (withANGLE) {
		if (hasANGLECommand) {
			return NO;
		}
		return replaceDylibPath(header, openGlesLoadCmd, ANGLELoadCmd);
	}

	if (hasOpenGLESCommand) {
		return NO;
	}
	return replaceDylibPath(header, ANGLELoadCmd, openGlesLoadCmd);
}

NSString* LCParseMachO(const char* path, bool readOnly, LCParseMachOCallback callback) {
	int fd = open(path, readOnly ? O_RDONLY : O_RDWR);
	if (fd < 0) {
		NSString* message = [NSString stringWithFormat:@"Failed to open %s: %s", path, strerror(errno)];
		AppLog(@"LCParseMachO error: %@", message);
		return message;
	}

	struct stat s;
	if (fstat(fd, &s) != 0) {
		NSString* message = [NSString stringWithFormat:@"Failed to stat %s: %s", path, strerror(errno)];
		AppLog(@"LCParseMachO error: %@", message);
		close(fd);
		return message;
	}

	if (s.st_size < sizeof(uint32_t)) {
		NSString* message = [NSString stringWithFormat:@"File is too small to be Mach-O: %s", path];
		AppLog(@"LCParseMachO error: %@", message);
		close(fd);
		return message;
	}

	void* map = mmap(NULL, s.st_size, readOnly ? PROT_READ : (PROT_READ | PROT_WRITE), readOnly ? MAP_PRIVATE : MAP_SHARED, fd, 0);
	if (map == MAP_FAILED) {
		NSString* message = [NSString stringWithFormat:@"Failed to map %s: %s", path, strerror(errno)];
		AppLog(@"LCParseMachO error: %@", message);
		close(fd);
		return message;
	}

	uint8_t* bytes = (uint8_t*)map;
	uint32_t magic = *(uint32_t*)map;
	BOOL handled = NO;

	if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
		BOOL swap = magic == FAT_CIGAM;
		struct fat_header* fat = (struct fat_header*)map;
		uint32_t count = swap ? OSSwapInt32(fat->nfat_arch) : fat->nfat_arch;

		if (sizeof(struct fat_header) + ((uint64_t)count * sizeof(struct fat_arch)) > (uint64_t)s.st_size) {
			munmap(map, s.st_size);
			close(fd);
			return @"Fat Mach-O header is outside file bounds";
		}

		struct fat_arch* arch = (struct fat_arch*)((uint8_t*)map + sizeof(struct fat_header));

		for (uint32_t i = 0; i < count; i++) {
			cpu_type_t cpuType = swap ? OSSwapInt32(arch->cputype) : arch->cputype;
			uint32_t offset = swap ? OSSwapInt32(arch->offset) : arch->offset;

			if (cpuType == CPU_TYPE_ARM64) {
				if ((uint64_t)offset + sizeof(struct mach_header_64) > (uint64_t)s.st_size) {
					munmap(map, s.st_size);
					close(fd);
					return @"ARM64 slice offset is outside file";
				}

				struct mach_header_64* header = (struct mach_header_64*)((uint8_t*)map + offset);
				if (header->magic != MH_MAGIC_64) {
					munmap(map, s.st_size);
					close(fd);
					return @"ARM64 slice is not MH_MAGIC_64";
				}

				callback(path, header, fd, map);
				handled = YES;
				break;
			}

			arch = (struct fat_arch*)((uint8_t*)arch + sizeof(struct fat_arch));
		}

		if (!handled) {
			munmap(map, s.st_size);
			close(fd);
			return @"No arm64 slice found in fat Mach-O";
		}
	} else if (magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64) {
		BOOL swap = magic == FAT_CIGAM_64;
		struct fat_header* fat = (struct fat_header*)map;
		uint32_t count = swap ? OSSwapInt32(fat->nfat_arch) : fat->nfat_arch;

		if (sizeof(struct fat_header) + ((uint64_t)count * sizeof(struct fat_arch_64)) > (uint64_t)s.st_size) {
			munmap(map, s.st_size);
			close(fd);
			return @"Fat64 Mach-O header is outside file bounds";
		}

		struct fat_arch_64* arch = (struct fat_arch_64*)((uint8_t*)map + sizeof(struct fat_header));

		for (uint32_t i = 0; i < count; i++) {
			cpu_type_t cpuType = swap ? OSSwapInt32(arch->cputype) : arch->cputype;
			uint64_t offset = swap ? OSSwapInt64(arch->offset) : arch->offset;

			if (cpuType == CPU_TYPE_ARM64) {
				if (offset + sizeof(struct mach_header_64) > (uint64_t)s.st_size) {
					munmap(map, s.st_size);
					close(fd);
					return @"ARM64 slice offset is outside file";
				}

				struct mach_header_64* header = (struct mach_header_64*)((uint8_t*)map + offset);
				if (header->magic != MH_MAGIC_64) {
					munmap(map, s.st_size);
					close(fd);
					return @"ARM64 slice is not MH_MAGIC_64";
				}

				callback(path, header, fd, map);
				handled = YES;
				break;
			}

			arch = (struct fat_arch_64*)((uint8_t*)arch + sizeof(struct fat_arch_64));
		}

		if (!handled) {
			munmap(map, s.st_size);
			close(fd);
			return @"No arm64 slice found in fat64 Mach-O";
		}
	} else if (magic == MH_MAGIC_64) {
		callback(path, (struct mach_header_64*)map, fd, map);
		handled = YES;
	} else if (magic == MH_MAGIC) {
		munmap(map, s.st_size);
		close(fd);
		AppLog(@"LCParseMachO error: 32-bit app is not supported");
		return @"32-bit app is not supported";
	} else {
		NSString* message = [NSString stringWithFormat:@"Not a Mach-O file. First bytes: %02x %02x %02x %02x", bytes[0], bytes[1], bytes[2], bytes[3]];
		AppLog(@"LCParseMachO error: %@", message);
		munmap(map, s.st_size);
		close(fd);
		return message;
	}

	if (!readOnly) {
		msync(map, s.st_size, MS_SYNC);
	}

	munmap(map, s.st_size);
	close(fd);
	return nil;
}

void LCChangeExecUUID(struct mach_header_64* header) {
	uint8_t* imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
	struct load_command* command = (struct load_command*)imageHeaderPtr;
	for (int i = 0; i < header->ncmds; i++) {
		if (command->cmd == LC_UUID) {
			struct uuid_command* uuidCmd = (struct uuid_command*)command;
			// let's add the first byte by 1
			uuidCmd->uuid[0] += 1;
			break;
		}
		command = (struct load_command*)((void*)command + command->cmdsize);
	}
}

struct code_signature_command {
	uint32_t cmd;
	uint32_t cmdsize;
	uint32_t dataoff;
	uint32_t datasize;
};

// from zsign
struct ui_CS_BlobIndex {
	uint32_t type;	 /* type of entry */
	uint32_t offset; /* offset of entry */
};

struct ui_CS_SuperBlob {
	uint32_t magic;	 /* magic number */
	uint32_t length; /* total length of SuperBlob */
	uint32_t count;	 /* number of index entries following */
					 // CS_BlobIndex index[];            /* (count) entries */
					 /* followed by Blobs in no particular order as indicated by offsets in index */
};

struct ui_CS_blob {
	uint32_t magic;
	uint32_t length;
};

struct code_signature_command* findSignatureCommand(struct mach_header_64* header) {
	uint8_t* imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
	struct load_command* command = (struct load_command*)imageHeaderPtr;
	struct code_signature_command* codeSignCommand = 0;
	for (int i = 0; i < header->ncmds; i++) {
		if (command->cmd == LC_CODE_SIGNATURE) {
			codeSignCommand = (struct code_signature_command*)command;
			break;
		}
		command = (struct load_command*)((void*)command + command->cmdsize);
	}
	return codeSignCommand;
}

NSString* getLCEntitlementXML(void) {
	struct mach_header_64* header = dlsym(RTLD_MAIN_ONLY, MH_EXECUTE_SYM);
	struct code_signature_command* codeSignCommand = findSignatureCommand(header);

	if (!codeSignCommand) {
		return @"Unable to find LC_CODE_SIGNATURE command.";
	}
	struct ui_CS_SuperBlob* blob = (void*)header + codeSignCommand->dataoff;
	if (blob->magic != OSSwapInt32(0xfade0cc0)) {
		return [NSString stringWithFormat:@"CodeSign blob magic mismatch %8x.", blob->magic];
	}
	struct ui_CS_BlobIndex* entitlementBlobIndex = 0;
	struct ui_CS_BlobIndex* nowIndex = (void*)blob + sizeof(struct ui_CS_SuperBlob);
	for (int i = 0; i < OSSwapInt32(blob->count); i++) {
		if (OSSwapInt32(nowIndex->type) == 5) {
			entitlementBlobIndex = nowIndex;
			break;
		}
		nowIndex = (void*)nowIndex + sizeof(struct ui_CS_BlobIndex);
	}
	if (entitlementBlobIndex == 0) {
		return @"[LC] entitlement blob index not found.";
	}
	struct ui_CS_blob* entitlementBlob = (void*)blob + OSSwapInt32(entitlementBlobIndex->offset);
	if (entitlementBlob->magic != OSSwapInt32(0xfade7171)) {
		return [NSString stringWithFormat:@"EntitlementBlob magic mismatch %8x.", blob->magic];
	};
	int32_t xmlLength = OSSwapInt32(entitlementBlob->length) - sizeof(struct ui_CS_blob);
	void* xmlPtr = (void*)entitlementBlob + sizeof(struct ui_CS_blob);

	// entitlement xml in executable don't have \0 so we have to copy it first
	char* xmlString = malloc(xmlLength + 1);
	memcpy(xmlString, xmlPtr, xmlLength);
	xmlString[xmlLength] = 0;

	NSString* ans = [NSString stringWithUTF8String:xmlString];
	free(xmlString);
	return ans;
}

bool checkCodeSignature(const char* path) {
	__block bool checked = false;
	__block bool ans = false;
	LCParseMachO(path, true, ^(const char* path, struct mach_header_64* header, int fd, void* filePtr) {
		if (checked || header->cputype != CPU_TYPE_ARM64) {
			return;
		}
		checked = true;
		struct code_signature_command* codeSignatureCommand = findSignatureCommand(header);
		if (!codeSignatureCommand) {
			AppLog(@"Couldn't find sig command for header");
			return;
		}
		off_t sliceOffset = (void*)header - filePtr;
		fsignatures_t siginfo;
		siginfo.fs_file_start = sliceOffset;
		siginfo.fs_blob_start = (void*)(long)(codeSignatureCommand->dataoff);
		siginfo.fs_blob_size = codeSignatureCommand->datasize;
		int addFileSigsReault = fcntl(fd, F_ADDFILESIGS_RETURN, &siginfo);
		if (addFileSigsReault == -1) {
			AppLog(@"F_ADDFILESIGS_RETURN failed: %s (%d). If you are running this in LiveContainer, please enable \"Fix File Picker & Local Notification\"", strerror(errno),
				   errno);
			ans = false;
			return;
		}
		fchecklv_t checkInfo;
		char messageBuffer[512];
		messageBuffer[0] = '\0';
		checkInfo.lv_error_message_size = sizeof(messageBuffer);
		checkInfo.lv_error_message = messageBuffer;
		checkInfo.lv_file_start = sliceOffset;
		int checkLVresult = fcntl(fd, F_CHECK_LV, &checkInfo);

		if (checkLVresult == 0) {
			ans = true;
			return;
		} else {
			AppLog(@"F_CHECK_LV failed: %s (%d)", strerror(errno), errno);
			ans = false;
			return;
		}
	});
	return ans;
}
