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

    fn run(self, input: &[f64]) -> Vec<f64> {
        let mut output = Vec::with_capacity(input.len());
        let (mut x1, mut x2, mut y1, mut y2) = (0.0, 0.0, 0.0, 0.0);
        for &x0 in input {
            let y0 = self.b0 * x0 + self.b1 * x1 + self.b2 * x2 - self.a1 * y1 - self.a2 * y2;
            output.push(y0);
            x2 = x1;
            x1 = x0;
            y2 = y1;
            y1 = y0;
        }
        output
    }
}

/// Maps the UI's 0–1 steepness setting to stable, even Butterworth orders.
pub fn butterworth_order(steepness: f64) -> usize {
    let steepness = steepness.clamp(0.0, 1.0);
    if steepness < 0.25 {
        2
    } else if steepness < 0.75 {
        4
    } else if steepness < 0.9 {
        6
    } else {
        8
    }
}

fn butterworth_sections(
    sample_rate: f64,
    cutoff_hz: f64,
    order: usize,
    mode: BiquadMode,
) -> Vec<Biquad> {
    (0..order / 2)
        .map(|section_index| {
            // Run the lower-Q sections first to keep intermediate values tame.
            let section = order / 2 - 1 - section_index;
            let angle = (2 * section + 1) as f64 * PI / (2 * order) as f64;
            let q = 1.0 / (2.0 * angle.sin());
            Biquad::cookbook(sample_rate, cutoff_hz, q, mode)
        })
        .collect()
}

fn odd_reflection_pad(input: &[f64], pad_length: usize) -> Vec<f64> {
    if input.len() < 2 || pad_length == 0 {
        return input.to_vec();
    }
    let pad_length = pad_length.min(input.len() - 1);
    let mut padded = Vec::with_capacity(input.len() + 2 * pad_length);
    for index in (1..=pad_length).rev() {
        padded.push(2.0 * input[0] - input[index]);
    }
    padded.extend_from_slice(input);
    let last = input.len() - 1;
    for index in 1..=pad_length {
        padded.push(2.0 * input[last] - input[last - index]);
    }
    padded
}

fn zero_phase_filter(input: &[f64], sections: &[Biquad], settling_pad: usize) -> Vec<f64> {
    if sections.is_empty() || input.len() < 2 {
        return input.to_vec();
    }
    let pad_length = settling_pad.max(sections.len() * 6).min(input.len() - 1);
    let mut current = odd_reflection_pad(input, pad_length);
    for section in sections {
        current = section.run(&current);
    }
    current.reverse();
    for section in sections {
        current = section.run(&current);
    }
    current.reverse();
    current[pad_length..pad_length + input.len()].to_vec()
}

/// Applies reflection-padded, forward/backward filtering to one continuous
/// channel. Cutoffs must describe a valid passband inside Nyquist.
pub fn bandpass_filter(
    input: &[f64],
    sample_rate: f64,
    low_cut_hz: f64,
    high_cut_hz: f64,
    steepness: f64,
    notch_hz: Option<f64>,
) -> Option<Vec<f64>> {
    if input.is_empty()
        || input.iter().any(|value| !value.is_finite())
        || !sample_rate.is_finite()
        || sample_rate <= 0.0
        || !low_cut_hz.is_finite()
        || !high_cut_hz.is_finite()
        || low_cut_hz < 0.0
        || high_cut_hz < 0.0
        || !steepness.is_finite()
        || !(0.0..=1.0).contains(&steepness)
        || notch_hz.is_some_and(|value| !value.is_finite())
    {
        return None;
    }

    let nyquist = sample_rate / 2.0;
    let low_enabled = low_cut_hz > 0.0;
    let high_enabled = high_cut_hz > 0.0;
    if (low_enabled && low_cut_hz >= nyquist)
        || (high_enabled && high_cut_hz >= nyquist)
        || (low_enabled && high_enabled && low_cut_hz >= high_cut_hz)
        || notch_hz.is_some_and(|value| value <= 0.0 || value >= nyquist)
    {
        return None;
    }

    let order = butterworth_order(steepness);
    let mut sections = Vec::new();
    if low_enabled {
        sections.extend(butterworth_sections(
            sample_rate,
            low_cut_hz,
            order,
            BiquadMode::HighPass,
        ));
    }
    if high_enabled {
        sections.extend(butterworth_sections(
            sample_rate,
            high_cut_hz,
            order,
            BiquadMode::LowPass,
        ));
    }
    // Preserve the existing notch design; only run it bidirectionally with
    // the other sections so the complete operation remains zero phase.
    if let Some(notch_hz) = notch_hz {
        let notch_q = (0.6 + steepness * 3.4).max(1.0);
        sections.push(Biquad::cookbook(
            sample_rate,
            notch_hz,
            notch_q,
            BiquadMode::Notch,
        ));
    }
    let slowest_frequency = if low_enabled {
        low_cut_hz
    } else if high_enabled {
        high_cut_hz
    } else {
        notch_hz.unwrap_or(nyquist)
    };
    let settling_pad = (10.0 * sample_rate / slowest_frequency).ceil() as usize;
    Some(zero_phase_filter(input, &sections, settling_pad))
}

#[cfg(test)]
mod tests {
    use super::{bandpass_filter, butterworth_order};
    use std::f64::consts::PI;

    #[test]
    fn maps_steepness_to_sensible_orders() {
        assert_eq!(butterworth_order(0.15), 2);
        assert_eq!(butterworth_order(0.5), 4);
        assert_eq!(butterworth_order(0.8), 6);
        assert_eq!(butterworth_order(1.0), 8);
    }

    #[test]
    fn preserves_length_and_filters_high_frequency_noise() {
        let sample_rate = 256.0;
        let input: Vec<f64> = (0..1024)
            .map(|index| {
                let time = index as f64 / sample_rate;
                (2.0 * PI * 10.0 * time).sin() + (2.0 * PI * 90.0 * time).sin()
            })
            .collect();
        let output = bandpass_filter(&input, sample_rate, 1.0, 40.0, 0.5, None).unwrap();
        assert_eq!(output.len(), input.len());
        assert!(output.iter().all(|value| value.is_finite()));
    }

    #[test]
    fn bidirectional_filter_has_no_measurable_phase_shift() {
        let sample_rate = 256.0;
        let input: Vec<f64> = (0..2048)
            .map(|index| (2.0 * PI * 10.0 * index as f64 / sample_rate).sin())
            .collect();
        let output = bandpass_filter(&input, sample_rate, 1.0, 40.0, 0.5, None).unwrap();
        let mut in_phase = 0.0;
        let mut quadrature = 0.0;
        for (index, value) in output.iter().enumerate().skip(128).take(input.len() - 256) {
            let angle = 2.0 * PI * 10.0 * index as f64 / sample_rate;
            in_phase += value * angle.sin();
            quadrature += value * angle.cos();
        }
        assert!(
            quadrature.abs() < in_phase.abs() * 1.0e-4,
            "quadrature component was {quadrature} versus {in_phase} in phase"
        );
    }

    #[test]
    fn rejects_invalid_cutoffs() {
        let input = vec![0.0; 128];
        assert!(bandpass_filter(&input, 256.0, 40.0, 20.0, 0.5, None).is_none());
        assert!(bandpass_filter(&input, 256.0, 1.0, 128.0, 0.5, None).is_none());
        assert!(bandpass_filter(&input, 256.0, 1.0, 40.0, 1.5, None).is_none());
        assert!(bandpass_filter(&input, 256.0, -1.0, 40.0, 0.5, None).is_none());
    }

    #[test]
    fn standard_low_pass_has_bounded_step_response() {
        let input: Vec<f64> = (0..1024)
            .map(|index| if index < 512 { 0.0 } else { 1.0 })
            .collect();
        let output = bandpass_filter(&input, 256.0, 0.0, 40.0, 0.5, None).unwrap();
        let minimum = output.iter().copied().fold(f64::INFINITY, f64::min);
        let maximum = output.iter().copied().fold(f64::NEG_INFINITY, f64::max);

        assert!(minimum > -0.1, "step undershoot was {minimum}");
        assert!(maximum < 1.1, "step overshoot was {maximum}");
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
        let without = bandpass_filter(&input, sample_rate, 1.0, 100.0, 0.5, None).unwrap();
        let with = bandpass_filter(&input, sample_rate, 1.0, 100.0, 0.5, Some(60.0)).unwrap();
        let amplitude = |values: &[f64]| {
            values
                .iter()
                .enumerate()
                .skip(128)
                .take(values.len() - 256)
                .map(|(index, value)| value * (2.0 * PI * 60.0 * index as f64 / sample_rate).sin())
                .sum::<f64>()
                .abs()
        };
        assert!(amplitude(&with) < amplitude(&without) * 0.05);
    }
}
