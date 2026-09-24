#ifndef RUNNER_OBSIDIAN_DESKTOP_H_
#define RUNNER_OBSIDIAN_DESKTOP_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

void RegisterObsidianDesktop(flutter::BinaryMessenger* messenger, HWND owner,
                             HWND flutter_view);
void ShutdownObsidianDesktop();

#endif  // RUNNER_OBSIDIAN_DESKTOP_H_
