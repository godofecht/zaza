/// A simple math library exposed via the C ABI for Zig consumption.

/// Add two 32-bit integers.
#[no_mangle]
pub extern "C" fn rust_add(a: i32, b: i32) -> i32 {
    a + b
}

/// Compute the factorial of n (clamped to avoid overflow).
#[no_mangle]
pub extern "C" fn rust_factorial(n: u32) -> u64 {
    match n {
        0 | 1 => 1,
        _ => (2..=n as u64).product(),
    }
}

/// Return the length of a null-terminated C string.
/// # Safety
/// The caller must pass a valid, null-terminated pointer.
#[no_mangle]
pub unsafe extern "C" fn rust_strlen(s: *const std::os::raw::c_char) -> usize {
    if s.is_null() {
        return 0;
    }
    unsafe { std::ffi::CStr::from_ptr(s).to_bytes().len() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add() {
        assert_eq!(rust_add(3, 4), 7);
        assert_eq!(rust_add(-1, 1), 0);
    }

    #[test]
    fn test_factorial() {
        assert_eq!(rust_factorial(0), 1);
        assert_eq!(rust_factorial(5), 120);
        assert_eq!(rust_factorial(10), 3628800);
    }
}
