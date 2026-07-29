use std::f64::consts::PI;

#[derive(Clone, Copy)]
enum BiquadMode {
    LowPass,
    HighPass,
    Notch,
}

#[derive(Clone, Copy)]
struct Biquad {
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
}

impl Biquad {
    fn cookbook(sample_rate: f64, frequency: f64, q: f64, mode: BiquadMode) -> Self {
        let omega = 2.0 * PI * frequency / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let (b0, b1, b2) = match mode {
            BiquadMode::LowPass => (
                (1.0 - cos_omega) / 2.0,
                1.0 - cos_omega,
                (1.0 - cos_omega) / 2.0,
            ),
            BiquadMode::HighPass => (
                (1.0 + cos_omega) / 2.0,
                -(1.0 + cos_omega),
                (1.0 + cos_omega) / 2.0,
            ),
            BiquadMode::Notch => (1.0, -2.0 * cos_omega, 1.0),
        };
        let a0 = 1.0 + alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: (-2.0 * cos_omega) / a0,
            a2: (1.0 - alpha) / a0,
        }
    }

    fn run(self, input: &[f64], output: &mut [f64]) {
        let (mut x1, mut x2, mut y1, mut y2) = (0.0, 0.0, 0.0, 0.0);
        for (&x0, y0) in input.iter().zip(output.iter_mut()) {
            *y0 = self.b0 * x0 + self.b1 * x1 + self.b2 * x2 - self.a1 * y1 - self.a2 * y2;
            x2 = x1;
            x1 = x0;
            y2 = y1;
            y1 = *y0;
        }
    }
}

/// Applies the same high-pass, low-pass, and optional notch cascade used by the
/// application. A cutoff outside `(0, Nyquist)` disables that stage.
pub fn bandpass_filter(
    input: &[f64],
    sample_rate: f64,
    low_cut_hz: f64,
    high_cut_hz: f64,
    steepness: f64,
    notch_hz: Option<f64>,
) -> Option<Vec<f64>> {
    if !sample_rate.is_finite()
        || sample_rate <= 0.0
        || !low_cut_hz.is_finite()
        || !high_cut_hz.is_finite()
        || !steepness.is_finite()
        || notch_hz.is_some_and(|value| !value.is_finite())
    {
        return None;
    }

    let nyquist = sample_rate / 2.0;
    let q = 0.6 + steepness.clamp(0.0, 1.0) * 3.4;
    let mut current = input.to_vec();
    let mut scratch = vec![0.0; input.len()];

    let mut apply = |filter: Biquad| {
        filter.run(&current, &mut scratch);
        std::mem::swap(&mut current, &mut scratch);
    };

    if low_cut_hz > 0.0 && low_cut_hz < nyquist {
        apply(Biquad::cookbook(
            sample_rate,
            low_cut_hz,
            q,
            BiquadMode::HighPass,
        ));
    }
    if high_cut_hz > 0.0 && high_cut_hz < nyquist {
        apply(Biquad::cookbook(
            sample_rate,
            high_cut_hz,
            q,
            BiquadMode::LowPass,
        ));
    }
    if let Some(notch_hz) = notch_hz.filter(|value| *value > 0.0 && *value < nyquist) {
        apply(Biquad::cookbook(
            sample_rate,
            notch_hz,
            q.max(1.0),
            BiquadMode::Notch,
        ));
    }

    Some(current)
}

#[cfg(test)]
mod tests {
    use super::bandpass_filter;
    use std::f64::consts::PI;

    #[test]
    fn preserves_length_and_changes_filtered_signal() {
        let input: Vec<f64> = (0..512)
            .map(|index| if index % 2 == 0 { 1.0 } else { -1.0 })
            .collect();
        let output = bandpass_filter(&input, 256.0, 1.0, 40.0, 0.8, Some(60.0)).unwrap();

        assert_eq!(output.len(), input.len());
        assert!((output[0] - input[0]).abs() > 0.0001);
    }

    #[test]
    fn notch_attenuates_its_center_frequency() {
        let sample_rate = 256.0;
        let input: Vec<f64> = (0..2048)
            .map(|index| {
                let time = index as f64 / sample_rate;
                (2.0 * PI * 60.0 * time).sin() + 0.25 * (2.0 * PI * 10.0 * time).sin()
            })
            .collect();
        let without = bandpass_filter(&input, sample_rate, 1.0, 100.0, 0.8, None).unwrap();
        let with = bandpass_filter(&input, sample_rate, 1.0, 100.0, 0.8, Some(60.0)).unwrap();
        let amplitude = |values: &[f64]| {
            values
                .iter()
                .enumerate()
                .map(|(index, value)| value * (2.0 * PI * 60.0 * index as f64 / sample_rate).sin())
                .sum::<f64>()
                .abs()
        };

        assert!(amplitude(&with) < amplitude(&without) * 0.2);
    }
}
