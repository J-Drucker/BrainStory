use std::slice;

pub const STATUS_OK: i32 = 0;
pub const STATUS_INVALID_ARGUMENT: i32 = 1;

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
    use super::{brainstory_segment_mean_sd, STATUS_OK};

    #[test]
    fn computes_mean_and_sd_for_flattened_traces() {
        let traces = vec![
            1.0_f64, 3.0, 5.0, //
            3.0_f64, 5.0, 7.0, //
        ];
        let mut mean = vec![0.0_f64; 3];
        let mut sd = vec![0.0_f64; 3];

        let status = brainstory_segment_mean_sd(
            traces.as_ptr(),
            2,
            3,
            mean.as_mut_ptr(),
            sd.as_mut_ptr(),
        );

        assert_eq!(status, STATUS_OK);
        assert_eq!(mean, vec![2.0, 4.0, 6.0]);
        assert_eq!(sd, vec![1.0, 1.0, 1.0]);
    }
}
