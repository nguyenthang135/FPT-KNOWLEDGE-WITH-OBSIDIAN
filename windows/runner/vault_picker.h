#ifndef RUNNER_VAULT_PICKER_H_
#define RUNNER_VAULT_PICKER_H_
#include <flutter/binary_messenger.h>
#include <windows.h>
void RegisterVaultPicker(flutter::BinaryMessenger* messenger, HWND owner);
#endif
