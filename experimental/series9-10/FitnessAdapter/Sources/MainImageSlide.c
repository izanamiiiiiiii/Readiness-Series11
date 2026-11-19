#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <dlfcn.h>
#include <string.h>
#include <stdint.h>

// The recovered bridge assumes image zero is the main executable. Resolve its
// own call by the executable's file type instead, preserving every other caller.
static intptr_t readiness_main_image_slide(uint32_t index) {
    Dl_info caller = {0};
    if (index == 0 && dladdr(__builtin_return_address(0), &caller) && caller.dli_fname &&
        strstr(caller.dli_fname, "/ReadinessBridge.framework/ReadinessBridge")) {
        for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
            const struct mach_header *header = _dyld_get_image_header(i);
            if (header && header->filetype == MH_EXECUTE) {
                const struct mach_header_64 *h = (const struct mach_header_64 *)header;
                const struct load_command *cmd = (const struct load_command *)(h + 1);
                for (uint32_t n = 0; n < h->ncmds; ++n) {
                    if (cmd->cmd == LC_SEGMENT_64) {
                        const struct segment_command_64 *segment = (const struct segment_command_64 *)cmd;
                        if (!strcmp(segment->segname, "__TEXT"))
                            return (intptr_t)header - (intptr_t)segment->vmaddr;
                    }
                    cmd = (const struct load_command *)((const char *)cmd + cmd->cmdsize);
                }
            }
        }
    }
    return _dyld_get_image_vmaddr_slide(index);
}
__attribute__((used,section("__DATA,__interpose")))
static const struct { const void *replacement; const void *replacee; } slide_interpose = {
    (const void *)(uintptr_t)&readiness_main_image_slide,
    (const void *)(uintptr_t)&_dyld_get_image_vmaddr_slide
};
