use std::ffi::CString;
use std::os::raw::c_char;
use std::slice;

use crate::filtering::bandpass_filter;
use crate::gaussian_mixture::fit_gaussian_mixture;
use crate::ica::{apply_unmixing_flat_into, fast_ica, fit_fast_ica};
use crate::spectrum::single_sided_spectrum;
use crate::wavelet::morlet_power;
use serde_json::json;

pub const STATUS_OK: i32 = 0;
pub const STATUS_INVALID_ARGUMENT: i32 = 1;

#[no_mangle]
pub extern "C" fn brainstory_gaussian_mixture(
    samples_ptr: *const f64,
    row_count: usize,
    feature_count: usize,
    component_count: usize,
    tolerance: f64,
    max_iterations: usize,
    regularization: f64,
    standardize: i32,
    seed: u64,
) -> *mut c_char {
    let result = if samples_ptr.is_null() || row_count == 0 || feature_count == 0 {
        None
    } else {
        let flat = unsafe { slice::from_raw_parts(samples_ptr, row_count * feature_count) };
        let rows: Vec<Vec<f64>> = flat
            .chunks_exact(feature_count)
            .map(|row| row.to_vec())
            .collect();
        fit_gaussian_mixture(
            &rows,
            component_count,
            tolerance,
            max_iterations,
            regularization,
            standardize != 0,
            seed,
        )
    };
    let payload = match result {
        Some(result) => json!({"ok": true, "result": result}),
        None => json!({"ok": false, "error": "Invalid Gaussian mixture input."}),
    };
    CString::new(payload.to_string())
        .expect("JSON cannot contain NUL bytes")
        .into_raw()
}

#[no_mangle]
pub extern "C" fn brainstory_morlet_wavelet(
    samples_ptr: *const f64,
    sample_count: usize,
    sample_rate: f64,
    low_hz: f64,
    high_hz: f64,
    frequency_count: usize,
    time_count: usize,
    cycles: f64,
) -> *mut c_char {
    let result = if samples_ptr.is_null() {
        None
    } else {
        let samples = unsafe { slice::from_raw_parts(samples_ptr, sample_count) };
        morlet_power(
            samples,
            sample_rate,
            low_hz,
            high_hz,
            frequency_count,
            time_count,
            cycles,
        )
    };
    let payload = match result {
        Some(result) => json!({"ok": true, "result": result}),
        None => json!({"ok": false, "error": "Invalid Morlet wavelet input."}),
    };
    CString::new(payload.to_string())
        .expect("JSON cannot contain NUL bytes")
        .into_raw()
}

#[no_mangle]
pub extern "C" fn brainstory_fast_ica(
    samples_ptr: *const f64,
    channel_count: usize,
    sample_count: usize,
    component_count: usize,
    tolerance: f64,
    max_iterations: usize,
    seed: u64,
) -> *mut c_char {
    let result = if samples_ptr.is_null() {
        Err("ICA did not receive a sample buffer.".to_string())
    } else if let Some(value_count) = channel_count.checked_mul(sample_count) {
        let samples = unsafe { slice::from_raw_parts(samples_ptr, value_count) };
        fast_ica(
            samples,
            channel_count,
            sample_count,
            component_count,
            tolerance,
            max_iterations,
            seed,
        )
    } else {
        Err("ICA input dimensions overflowed the native address space.".to_string())
    };
    let payload = match result {
        Ok(result) => json!({"ok": true, "result": result}),
        Err(error) => json!({"ok": false, "error": error}),
    };
    CString::new(payload.to_string())
        .expect("JSON cannot contain NUL bytes")
        .into_raw()
}

/// Fits ICA and returns only the compact model metadata as JSON. Component
/// activations are intentionally omitted so bulk sample data can travel
/// through `brainstory_apply_ica`'s typed buffers instead of JSON.
#[no_mangle]
pub extern "C" fn brainstory_fast_ica_fit(
    samples_ptr: *const f64,
    channel_count: usize,
    sample_count: usize,
    component_count: usize,
    tolerance: f64,
    max_iterations: usize,
    seed: u64,
) -> *mut c_char {
    let result = if samples_ptr.is_null() {
        Err("ICA did not receive a sample buffer.".to_string())
    } else if let Some(value_count) = channel_count.checked_mul(sample_count) {
        let samples = unsafe { slice::from_raw_parts(samples_ptr, value_count) };
        fit_fast_ica(
            samples,
            channel_count,
            sample_count,
            component_count,
            tolerance,
            max_iterations,
            seed,
        )
    } else {
        Err("ICA input dimensions overflowed the native address space.".to_string())
    };
    let payload = match result {
        Ok(result) => json!({"ok": true, "result": result}),
        Err(error) => json!({"ok": false, "error": error}),
    };
    CString::new(payload.to_string())
        .expect("JSON cannot contain NUL bytes")
        .into_raw()
}

#[no_mangle]
pub extern "C" fn brainstory_apply_ica(
    samples_ptr: *const f64,
    channel_count: usize,
    sample_count: usize,
    unmixing_ptr: *const f64,
    component_count: usize,
    channel_means_ptr: *const f64,
    output_ptr: *mut f64,
) -> i32 {
    if samples_ptr.is_null()
        || unmixing_ptr.is_null()
        || channel_means_ptr.is_null()
        || output_ptr.is_null()
    {
        return STATUS_INVALID_ARGUMENT;
    }
    let Some(sample_value_count) = channel_count.checked_mul(sample_count) else {
        return STATUS_INVALID_ARGUMENT;
    };
    let Some(matrix_value_count) = component_count.checked_mul(channel_count) else {
        return STATUS_INVALID_ARGUMENT;
    };
    let Some(output_value_count) = component_count.checked_mul(sample_count) else {
        return STATUS_INVALID_ARGUMENT;
    };
    let samples = unsafe { slice::from_raw_parts(samples_ptr, sample_value_count) };
    let unmixing = unsafe { slice::from_raw_parts(unmixing_ptr, matrix_value_count) };
    let channel_means = unsafe { slice::from_raw_parts(channel_means_ptr, channel_count) };
    let output = unsafe { slice::from_raw_parts_mut(output_ptr, output_value_count) };
    match apply_unmixing_flat_into(
        samples,
        channel_count,
        sample_count,
        unmixing,
        component_count,
        channel_means,
        output,
    ) {
        Ok(()) => STATUS_OK,
        Err(_) => STATUS_INVALID_ARGUMENT,
    }
}

#[no_mangle]
pub extern "C" fn brainstory_single_sided_spectrum(
    samples_ptr: *const f64,
    sample_count: usize,
    sample_rate: f64,
    low_hz: f64,
    high_hz: f64,
    frequencies_out_ptr: *mut f64,
    power_out_ptr: *mut f64,
    output_capacity: usize,
    bin_count_out_ptr: *mut usize,
) -> i32 {
    if samples_ptr.is_null()
        || frequencies_out_ptr.is_null()
        || power_out_ptr.is_null()
        || bin_count_out_ptr.is_null()
        || sample_count == 0
    {
        return STATUS_INVALID_ARGUMENT;
    }

    let samples = unsafe { slice::from_raw_parts(samples_ptr, sample_count) };
    let Some(spectrum) = single_sided_spectrum(samples, sample_rate, low_hz, high_hz) else {
        return STATUS_INVALID_ARGUMENT;
    };
    if spectrum.frequencies.len() > output_capacity {
        return STATUS_INVALID_ARGUMENT;
    }

    let frequencies_out =
        unsafe { slice::from_raw_parts_mut(frequencies_out_ptr, spectrum.frequencies.len()) };
    let power_out = unsafe { slice::from_raw_parts_mut(power_out_ptr, spectrum.power.len()) };
    frequencies_out.copy_from_slice(&spectrum.frequencies);
    power_out.copy_from_slice(&spectrum.power);
    unsafe { *bin_count_out_ptr = spectrum.frequencies.len() };
    STATUS_OK
}

#[no_mangle]
pub extern "C" fn brainstory_bandpass_filter(
    input_ptr: *const f64,
    sample_count: usize,
    sample_rate: f64,
    low_cut_hz: f64,
    high_cut_hz: f64,
    steepness: f64,
    notch_hz: f64,
    output_ptr: *mut f64,
) -> i32 {
    if input_ptr.is_null() || output_ptr.is_null() || sample_count == 0 {
        return STATUS_INVALID_ARGUMENT;
    }

    let input = unsafe { slice::from_raw_parts(input_ptr, sample_count) };
    let output = unsafe { slice::from_raw_parts_mut(output_ptr, sample_count) };
    let notch = if notch_hz.is_nan() {
        None
    } else {
        Some(notch_hz)
    };
    let Some(filtered) = bandpass_filter(
        input,
        sample_rate,
        low_cut_hz,
        high_cut_hz,
        steepness,
        notch,
    ) else {
        return STATUS_INVALID_ARGUMENT;
    };
    output.copy_from_slice(&filtered);
    STATUS_OK
}

#[no_mangle]
pub extern "C" fn brainstory_segment_mean_sd(
    traces_ptr: *const f64,
    trace_count: usize,
    sample_count: usize,
    mean_out_ptr: *mut f64,
    sd_out_ptr: *mut f64,
) -> i32 {
    if traces_ptr.is_null()
        || mean_out_ptr.is_null()
        || sd_out_ptr.is_null()
        || trace_count == 0
        || sample_count == 0
    {
        return STATUS_INVALID_ARGUMENT;
    }

    let trace_value_count = match trace_count.checked_mul(sample_count) {
        Some(count) => count,
        None => return STATUS_INVALID_ARGUMENT,
    };

    let traces = unsafe { slice::from_raw_parts(traces_ptr, trace_value_count) };
    let mean_out = unsafe { slice::from_raw_parts_mut(mean_out_ptr, sample_count) };
    let sd_out = unsafe { slice::from_raw_parts_mut(sd_out_ptr, sample_count) };

    for sample_index in 0..sample_count {
        let mut sum = 0.0;
        for trace_index in 0..trace_count {
            sum += traces[(trace_index * sample_count) + sample_index];
        }

        let mean = sum / trace_count as f64;
        mean_out[sample_index] = mean;

        let mut variance = 0.0;
        for trace_index in 0..trace_count {
            let delta = traces[(trace_index * sample_count) + sample_index] - mean;
            variance += delta * delta;
        }
        variance /= trace_count as f64;
        sd_out[sample_index] = variance.sqrt();
    }

    STATUS_OK
}

#[cfg(test)]
mod tests {
    use super::{
        brainstory_apply_ica, brainstory_bandpass_filter, brainstory_fast_ica,
        brainstory_fast_ica_fit, brainstory_gaussian_mixture, brainstory_morlet_wavelet,
        brainstory_segment_mean_sd, brainstory_single_sided_spectrum, STATUS_OK,
    };
    use crate::ant_cnt::brainstory_engine_free_string;
    use std::ffi::CStr;

    #[test]
    fn computes_mean_and_sd_for_flattened_traces() {
        let traces = vec![
            1.0_f64, 3.0, 5.0, //
            3.0_f64, 5.0, 7.0, //
        ];
        let mut mean = vec![0.0_f64; 3];
        let mut sd = vec![0.0_f64; 3];

        let status =
            brainstory_segment_mean_sd(traces.as_ptr(), 2, 3, mean.as_mut_ptr(), sd.as_mut_ptr());

        assert_eq!(status, STATUS_OK);
        assert_eq!(mean, vec![2.0, 4.0, 6.0]);
        assert_eq!(sd, vec![1.0, 1.0, 1.0]);
    }

    #[test]
    fn filters_through_the_c_api() {
        let input = vec![1.0_f64, -1.0, 1.0, -1.0];
        let mut output = vec![0.0_f64; input.len()];
        let status = brainstory_bandpass_filter(
            input.as_ptr(),
            input.len(),
            256.0,
            1.0,
            40.0,
            0.8,
            f64::NAN,
            output.as_mut_ptr(),
        );

        assert_eq!(status, STATUS_OK);
        assert_ne!(output, input);
    }

    #[test]
    fn computes_a_spectrum_through_the_c_api() {
        let input: Vec<f64> = (0..128).map(|index| (index as f64 / 4.0).sin()).collect();
        let capacity = input.len() / 2 + 1;
        let mut frequencies = vec![0.0; capacity];
        let mut power = vec![0.0; capacity];
        let mut bin_count = 0;
        let status = brainstory_single_sided_spectrum(
            input.as_ptr(),
            input.len(),
            128.0,
            1.0,
            40.0,
            frequencies.as_mut_ptr(),
            power.as_mut_ptr(),
            capacity,
            &mut bin_count,
        );

        assert_eq!(status, STATUS_OK);
        assert!(bin_count > 0);
        assert_eq!(frequencies[0], 1.0);
        assert!(power[..bin_count].iter().all(|value| value.is_finite()));
    }

    #[test]
    fn computes_wavelet_power_through_the_c_api() {
        let input: Vec<f64> = (0..128).map(|index| (index as f64 / 4.0).sin()).collect();
        let pointer =
            brainstory_morlet_wavelet(input.as_ptr(), input.len(), 128.0, 4.0, 20.0, 9, 41, 6.0);

        assert!(!pointer.is_null());
        let json = unsafe { CStr::from_ptr(pointer) }
            .to_string_lossy()
            .into_owned();
        brainstory_engine_free_string(pointer);
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["result"]["frequencies"].as_array().unwrap().len(), 9);
        assert_eq!(value["result"]["times"].as_array().unwrap().len(), 41);
        assert_eq!(value["result"]["powerMatrix"].as_array().unwrap().len(), 9);
    }

    #[test]
    fn fits_gaussian_mixture_through_the_c_api() {
        let rows = [-3.0_f64, -2.9, -3.1, -3.0, 4.0, 4.1, 3.9, 4.0];
        let pointer =
            brainstory_gaussian_mixture(rows.as_ptr(), 4, 2, 2, 1.0e-6, 200, 1.0e-6, 1, 42);

        assert!(!pointer.is_null());
        let json = unsafe { CStr::from_ptr(pointer) }
            .to_string_lossy()
            .into_owned();
        brainstory_engine_free_string(pointer);
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["result"]["assignments"].as_array().unwrap().len(), 4);
        assert_eq!(value["result"]["means"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn computes_ica_through_the_c_api() {
        let sample_count = 256;
        let mut samples = Vec::with_capacity(sample_count * 2);
        samples.extend((0..sample_count).map(|index| (index as f64 / 9.0).sin()));
        samples.extend(
            (0..sample_count)
                .map(|index| (index as f64 / 9.0).sin() + 0.5 * (index as f64 / 5.0).cos()),
        );
        let pointer = brainstory_fast_ica(samples.as_ptr(), 2, sample_count, 2, 1.0e-4, 500, 42);
        assert!(!pointer.is_null());
        let json = unsafe { CStr::from_ptr(pointer) }
            .to_string_lossy()
            .into_owned();
        brainstory_engine_free_string(pointer);
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["result"]["activations"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn fits_compact_ica_model_and_projects_through_typed_buffers() {
        let sample_count = 256;
        let mut samples = Vec::with_capacity(sample_count * 2);
        samples.extend((0..sample_count).map(|index| (index as f64 / 9.0).sin()));
        samples.extend(
            (0..sample_count)
                .map(|index| (index as f64 / 9.0).sin() + 0.5 * (index as f64 / 5.0).cos()),
        );
        let pointer =
            brainstory_fast_ica_fit(samples.as_ptr(), 2, sample_count, 2, 1.0e-4, 500, 42);
        assert!(!pointer.is_null());
        let json = unsafe { CStr::from_ptr(pointer) }
            .to_string_lossy()
            .into_owned();
        brainstory_engine_free_string(pointer);
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(value["ok"], true);
        assert!(value["result"].get("activations").is_none());
        let result = &value["result"];
        let unmixing: Vec<f64> = result["unmixingMatrix"]
            .as_array()
            .unwrap()
            .iter()
            .flat_map(|row| row.as_array().unwrap())
            .map(|entry| entry.as_f64().unwrap())
            .collect();
        let means: Vec<f64> = result["channelMeans"]
            .as_array()
            .unwrap()
            .iter()
            .map(|entry| entry.as_f64().unwrap())
            .collect();
        let mut output = vec![f64::NAN; 2 * sample_count];
        let status = brainstory_apply_ica(
            samples.as_ptr(),
            2,
            sample_count,
            unmixing.as_ptr(),
            2,
            means.as_ptr(),
            output.as_mut_ptr(),
        );
        assert_eq!(status, STATUS_OK);
        assert!(output.iter().all(|value| value.is_finite()));
        assert!(output.iter().any(|value| value.abs() > 0.1));
    }
}
