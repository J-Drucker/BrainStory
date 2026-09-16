use serde::Serialize;
use std::f64::consts::PI;

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WaveletPower {
    pub times: Vec<f64>,
    pub frequencies: Vec<f64>,
    pub power_matrix: Vec<Vec<f64>>,
}

pub fn morlet_power(
    samples: &[f64],
    sample_rate: f64,
    low_hz: f64,
    high_hz: f64,
    frequency_count: usize,
    time_count: usize,
    cycles: f64,
) -> Option<WaveletPower> {
    if samples.is_empty()
        || !sample_rate.is_finite()
        || sample_rate <= 0.0
        || !low_hz.is_finite()
        || !high_hz.is_finite()
        || low_hz <= 0.0
        || high_hz < low_hz
        || high_hz > sample_rate / 2.0
        || frequency_count == 0
        || frequency_count > 128
        || time_count == 0
        || time_count > 2048
        || !cycles.is_finite()
        || cycles < 2.0
        || cycles > 20.0
        || samples.iter().any(|value| !value.is_finite())
    {
        return None;
    }

    let output_time_count = time_count.min(samples.len());
    let mean = samples.iter().sum::<f64>() / samples.len() as f64;
    let centered: Vec<f64> = samples.iter().map(|value| value - mean).collect();
    let times: Vec<f64> = (0..output_time_count)
        .map(|index| {
            let sample = if output_time_count == 1 {
                0.0
            } else {
                index as f64 * (samples.len() - 1) as f64 / (output_time_count - 1) as f64
            };
            sample / sample_rate
        })
        .collect();
    let frequencies: Vec<f64> = (0..frequency_count)
        .map(|index| {
            if frequency_count == 1 {
                low_hz
            } else {
                low_hz + (high_hz - low_hz) * index as f64 / (frequency_count - 1) as f64
            }
        })
        .collect();

    let mut power_matrix = Vec::with_capacity(frequency_count);
    for &frequency in &frequencies {
        let sigma_seconds = cycles / (2.0 * PI * frequency);
        let half_width = (3.5 * sigma_seconds * sample_rate).ceil() as isize;
        let mut row = Vec::with_capacity(output_time_count);
        for time_index in 0..output_time_count {
            let center = if output_time_count == 1 {
                0
            } else {
                ((time_index as f64 * (samples.len() - 1) as f64 / (output_time_count - 1) as f64)
                    .round()) as isize
            };
            let start = (center - half_width).max(0);
            let stop = (center + half_width + 1).min(samples.len() as isize);
            let mut real = 0.0;
            let mut imaginary = 0.0;
            let mut norm = 0.0;
            for sample_index in start..stop {
                let offset_seconds = (sample_index - center) as f64 / sample_rate;
                let gaussian = (-0.5 * (offset_seconds / sigma_seconds).powi(2)).exp();
                let phase = 2.0 * PI * frequency * offset_seconds;
                let value = centered[sample_index as usize];
                real += value * gaussian * phase.cos();
                imaginary += value * gaussian * phase.sin();
                norm += gaussian * gaussian;
            }
            row.push(if norm > 0.0 {
                (real * real + imaginary * imaginary) / norm
            } else {
                0.0
            });
        }
        power_matrix.push(row);
    }

    Some(WaveletPower {
        times,
        frequencies,
        power_matrix,
    })
}

#[cfg(test)]
mod tests {
    use super::morlet_power;
    use std::f64::consts::PI;

    #[test]
    fn localizes_a_twelve_hertz_burst() {
        let sample_rate = 128.0;
        let samples: Vec<f64> = (0..256)
            .map(|index| {
                let time = index as f64 / sample_rate;
                if (0.75..1.25).contains(&time) {
                    (2.0 * PI * 12.0 * time).sin()
                } else {
                    0.0
                }
            })
            .collect();
        let result = morlet_power(&samples, sample_rate, 4.0, 20.0, 17, 81, 6.0).unwrap();
        let frequency_index = result
            .frequencies
            .iter()
            .enumerate()
            .min_by(|left, right| (left.1 - 12.0).abs().total_cmp(&(right.1 - 12.0).abs()))
            .unwrap()
            .0;
        let peak_time = result.times[result.power_matrix[frequency_index]
            .iter()
            .enumerate()
            .max_by(|left, right| left.1.total_cmp(right.1))
            .unwrap()
            .0];
        assert!((peak_time - 1.0).abs() < 0.2);
    }
}
