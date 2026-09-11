#[path = "../../src/filtering.rs"]
mod filtering;
#[path = "../../src/ica.rs"]
mod ica;
#[path = "../../src/spectrum.rs"]
mod spectrum;

use serde::Deserialize;
use serde_json::{json, Value};
use std::ffi::{c_char, CString};

#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "camelCase")]
enum Request {
    Filter {
        samples: Vec<f64>,
        rate: f64,
        low: f64,
        high: f64,
        steepness: f64,
        notch: Option<f64>,
    },
    Spectrum {
        samples: Vec<f64>,
        rate: f64,
        low: f64,
        high: f64,
    },
    Ica {
        channels: Vec<Vec<f64>>,
        components: usize,
        tolerance: f64,
        iterations: usize,
        seed: u64,
    },
    ApplyIca {
        channels: Vec<Vec<f64>>,
        matrix: Vec<Vec<f64>>,
        means: Vec<f64>,
    },
}

fn execute(request: Request) -> Result<Value, String> {
    match request {
        Request::Filter {
            samples,
            rate,
            low,
            high,
            steepness,
            notch,
        } => filtering::bandpass_filter(&samples, rate, low, high, steepness, notch)
            .map(|values| json!(values))
            .ok_or("Invalid filter input".into()),
        Request::Spectrum {
            samples,
            rate,
            low,
            high,
        } => spectrum::single_sided_spectrum(&samples, rate, low, high)
            .map(|s| json!({"frequencies": s.frequencies, "power": s.power}))
            .ok_or("Invalid spectrum input".into()),
        Request::Ica {
            channels,
            components,
            tolerance,
            iterations,
            seed,
        } => {
            let count = channels.len();
            let length = channel_length(&channels)?;
            let samples: Vec<f64> = channels.into_iter().flatten().collect();
            ica::fast_ica(
                &samples, count, length, components, tolerance, iterations, seed,
            )
            .and_then(|value| serde_json::to_value(value).map_err(|e| e.to_string()))
        }
        Request::ApplyIca {
            channels,
            matrix,
            means,
        } => {
            let count = channels.len();
            let length = channel_length(&channels)?;
            let samples: Vec<f64> = channels.into_iter().flatten().collect();
            ica::apply_unmixing(&samples, count, length, &matrix, &means).map(|v| json!(v))
        }
    }
}

fn channel_length(channels: &[Vec<f64>]) -> Result<usize, String> {
    let length = channels.first().map_or(0, Vec::len);
    if length == 0 || channels.iter().any(|c| c.len() != length) {
        return Err("Expected nonempty equal-length channels".into());
    }
    Ok(length)
}

#[no_mangle]
pub extern "C" fn allocate(length: usize) -> *mut u8 {
    Box::into_raw(vec![0u8; length].into_boxed_slice()) as *mut u8
}

#[no_mangle]
pub unsafe extern "C" fn release(pointer: *mut u8, length: usize) {
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        pointer, length,
    )));
}

#[no_mangle]
pub unsafe extern "C" fn run(pointer: *const u8, length: usize) -> *mut c_char {
    let result = serde_json::from_slice(std::slice::from_raw_parts(pointer, length))
        .map_err(|e| e.to_string())
        .and_then(execute);
    let payload = match result {
        Ok(value) => json!({"result": value}),
        Err(error) => json!({"error": error}),
    };
    CString::new(payload.to_string()).unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn release_result(pointer: *mut c_char) {
    drop(CString::from_raw(pointer));
}
