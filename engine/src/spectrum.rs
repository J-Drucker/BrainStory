use realfft::RealFftPlanner;

#[derive(Debug, Clone, PartialEq)]
pub struct Spectrum {
    pub frequencies: Vec<f64>,
    pub power: Vec<f64>,
}

/// Computes a single-sided power spectrum with an O(n log n) real FFT.
/// The caller is responsible for applying any desired window beforehand.
pub fn single_sided_spectrum(
    samples: &[f64],
    sample_rate: f64,
    low_hz: f64,
    high_hz: f64,
) -> Option<Spectrum> {
    if samples.is_empty()
        || !sample_rate.is_finite()
        || sample_rate <= 0.0
        || !low_hz.is_finite()
        || !high_hz.is_finite()
        || low_hz > high_hz
        || samples.iter().any(|value| !value.is_finite())
    {
        return None;
    }

    let sample_count = samples.len();
    let mut planner = RealFftPlanner::<f64>::new();
    let fft = planner.plan_fft_forward(sample_count);
    let mut input = samples.to_vec();
    let mut complex = fft.make_output_vec();
    fft.process(&mut input, &mut complex).ok()?;

    let mut frequencies = Vec::with_capacity(complex.len());
    let mut power = Vec::with_capacity(complex.len());
    for (index, value) in complex.iter().enumerate() {
        let frequency = index as f64 * sample_rate / sample_count as f64;
        if frequency >= low_hz && frequency <= high_hz {
            frequencies.push(frequency);
            power.push(value.norm_sqr() / sample_count as f64);
        }
    }

    Some(Spectrum { frequencies, power })
}

#[cfg(test)]
mod tests {
    use super::single_sided_spectrum;
    use std::f64::consts::PI;

    #[test]
    fn identifies_the_dominant_frequency() {
        let sample_rate = 256.0;
        let samples: Vec<f64> = (0..256)
            .map(|index| (2.0 * PI * 12.0 * index as f64 / sample_rate).sin())
            .collect();
        let spectrum = single_sided_spectrum(&samples, sample_rate, 1.0, 40.0).unwrap();
        let peak_index = spectrum
            .power
            .iter()
            .enumerate()
            .max_by(|left, right| left.1.total_cmp(right.1))
            .unwrap()
            .0;

        assert!((spectrum.frequencies[peak_index] - 12.0).abs() < f64::EPSILON);
    }

    #[test]
    fn limits_output_to_the_requested_band() {
        let samples = vec![1.0; 128];
        let spectrum = single_sided_spectrum(&samples, 128.0, 8.0, 12.0).unwrap();

        assert_eq!(spectrum.frequencies.first(), Some(&8.0));
        assert_eq!(spectrum.frequencies.last(), Some(&12.0));
        assert_eq!(spectrum.frequencies.len(), spectrum.power.len());
    }
}
