import 'dart:ffi';
import 'dart:io';

/// Hands the process's resident pages back to Windows.
///
/// The app spends most of the day sitting in the tray with nothing on screen,
/// where a ~100 MB working set is pure waste. Trimming drops it to a few MB;
/// Windows pages what is still needed back in when the window is shown again.
void trimWorkingSet() {
  if (!Platform.isWindows) return;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final currentProcess = kernel32
        .lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');
    final setWorkingSetSize = kernel32.lookupFunction<
        Int32 Function(IntPtr process, IntPtr min, IntPtr max),
        int Function(int process, int min, int max)>('SetProcessWorkingSetSize');
    // -1/-1 means "trim to the minimum you can".
    setWorkingSetSize(currentProcess(), -1, -1);
  } catch (_) {
    // Trimming is an optimisation; never let it break hiding the window.
  }
}
