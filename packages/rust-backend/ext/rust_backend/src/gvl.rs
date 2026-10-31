use std::ffi::c_void;

pub fn call_without_gvl<F, R>(f: F) -> R
where
    F: FnOnce() -> R + Send,
    R: Send,
{
    struct State<F, R> {
        f: Option<F>,
        result: Option<R>,
    }

    unsafe extern "C" fn runner<F, R>(data: *mut c_void) -> *mut c_void
    where
        F: FnOnce() -> R + Send,
        R: Send,
    {
        let state = &mut *(data as *mut State<F, R>);
        if let Some(f) = state.f.take() {
            state.result = Some(f());
        }
        std::ptr::null_mut()
    }

    let mut state = State {
        f: Some(f),
        result: None,
    };

    unsafe {
        rb_sys::rb_thread_call_without_gvl(
            Some(runner::<F, R>),
            &mut state as *mut _ as *mut c_void,
            None,
            std::ptr::null_mut(),
        );
    }

    state.result.expect("GVL callback finished")
}
