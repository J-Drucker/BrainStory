use nalgebra::{DMatrix, SymmetricEigen};
use serde::Serialize;

const MIN_EIGENVALUE_RATIO: f64 = 1.0e-12;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IcaResult {
    pub activations: Vec<Vec<f64>>,
    pub unmixing_matrix: Vec<Vec<f64>>,
    pub mixing_matrix: Vec<Vec<f64>>,
    pub whitening_matrix: Vec<Vec<f64>>,
    pub dewhitening_matrix: Vec<Vec<f64>>,
    pub channel_means: Vec<f64>,
    pub component_energies: Vec<f64>,
    pub converged: bool,
    pub iteration_count: usize,
    pub numerical_rank: usize,
    pub tolerance: f64,
    pub max_iterations: usize,
    pub seed: u64,
}

pub fn fast_ica(
    channel_major_samples: &[f64],
    channel_count: usize,
    sample_count: usize,
    requested_components: usize,
    tolerance: f64,
    max_iterations: usize,
    seed: u64,
) -> Result<IcaResult, String> {
    validate_input(
        channel_major_samples,
        channel_count,
        sample_count,
        requested_components,
        tolerance,
        max_iterations,
    )?;

    let input = DMatrix::from_row_slice(channel_count, sample_count, channel_major_samples);
    let channel_means: Vec<f64> = (0..channel_count)
        .map(|channel| input.row(channel).iter().sum::<f64>() / sample_count as f64)
        .collect();
    let centered = DMatrix::from_fn(channel_count, sample_count, |channel, sample| {
        input[(channel, sample)] - channel_means[channel]
    });
    let covariance = (&centered * centered.transpose()) / sample_count as f64;
    let covariance_eigen = SymmetricEigen::new(covariance);
    let mut eigen_order: Vec<usize> = (0..channel_count).collect();
    eigen_order.sort_by(|left, right| {
        covariance_eigen.eigenvalues[*right].total_cmp(&covariance_eigen.eigenvalues[*left])
    });
    let largest_eigenvalue = covariance_eigen.eigenvalues[eigen_order[0]];
    if !largest_eigenvalue.is_finite() || largest_eigenvalue <= 0.0 {
        return Err("ICA input has no non-zero channel variance.".to_string());
    }
    let eigenvalue_floor = (largest_eigenvalue * MIN_EIGENVALUE_RATIO).max(f64::EPSILON);
    let numerical_rank = eigen_order
        .iter()
        .take_while(|index| covariance_eigen.eigenvalues[**index] > eigenvalue_floor)
        .count();
    if numerical_rank < 2 {
        return Err(
            "ICA input must contain at least two linearly independent channels.".to_string(),
        );
    }
    let component_count = if requested_components == 0 {
        numerical_rank
    } else {
        requested_components
    };
    if component_count > numerical_rank {
        return Err(format!(
            "Requested {component_count} ICA components, but the input numerical rank is {numerical_rank}."
        ));
    }

    let mut whitening = DMatrix::zeros(component_count, channel_count);
    let mut dewhitening = DMatrix::zeros(channel_count, component_count);
    for component in 0..component_count {
        let eigen_index = eigen_order[component];
        let scale = covariance_eigen.eigenvalues[eigen_index].sqrt();
        for channel in 0..channel_count {
            let eigenvector_value = covariance_eigen.eigenvectors[(channel, eigen_index)];
            whitening[(component, channel)] = eigenvector_value / scale;
            dewhitening[(channel, component)] = eigenvector_value * scale;
        }
    }
    let whitened = &whitening * &centered;

    let mut random = DeterministicRandom::new(seed);
    let initial = DMatrix::from_fn(component_count, component_count, |_, _| {
        random.next_signed()
    });
    let mut unmix_whitened = symmetric_decorrelation(initial)?;
    let mut converged = false;
    let mut iteration_count = 0;
    for iteration in 1..=max_iterations {
        let projected = &unmix_whitened * &whitened;
        let nonlinearity = projected.map(f64::tanh);
        let derivative_means: Vec<f64> = (0..component_count)
            .map(|component| {
                projected
                    .row(component)
                    .iter()
                    .map(|value| {
                        let tanh = value.tanh();
                        1.0 - tanh * tanh
                    })
                    .sum::<f64>()
                    / sample_count as f64
            })
            .collect();
        let mut next = (&nonlinearity * whitened.transpose()) / sample_count as f64;
        for component in 0..component_count {
            for column in 0..component_count {
                next[(component, column)] -=
                    derivative_means[component] * unmix_whitened[(component, column)];
            }
        }
        next = symmetric_decorrelation(next)?;
        let convergence_delta = (0..component_count)
            .map(|component| {
                let alignment = next
                    .row(component)
                    .dot(&unmix_whitened.row(component))
                    .abs();
                (1.0 - alignment).abs()
            })
            .fold(0.0, f64::max);
        unmix_whitened = next;
        iteration_count = iteration;
        if convergence_delta < tolerance {
            converged = true;
            break;
        }
    }

    let unmixing = &unmix_whitened * &whitening;
    let mixing = &dewhitening * unmix_whitened.transpose();
    let activations = &unmix_whitened * whitened;
    let (activations, unmixing, mixing, component_energies) =
        normalize_components(activations, unmixing, mixing);

    Ok(IcaResult {
        activations: matrix_rows(&activations),
        unmixing_matrix: matrix_rows(&unmixing),
        mixing_matrix: matrix_rows(&mixing),
        whitening_matrix: matrix_rows(&whitening),
        dewhitening_matrix: matrix_rows(&dewhitening),
        channel_means,
        component_energies,
        converged,
        iteration_count,
        numerical_rank,
        tolerance,
        max_iterations,
        seed,
    })
}

fn validate_input(
    samples: &[f64],
    channel_count: usize,
    sample_count: usize,
    requested_components: usize,
    tolerance: f64,
    max_iterations: usize,
) -> Result<(), String> {
    if channel_count < 2 {
        return Err("ICA requires at least two channels.".to_string());
    }
    if sample_count < 32 || sample_count < channel_count * 3 {
        return Err(format!(
            "ICA requires at least 32 samples and at least three samples per channel; received {sample_count}."
        ));
    }
    if samples.len() != channel_count.saturating_mul(sample_count) {
        return Err("ICA input dimensions do not match the sample buffer.".to_string());
    }
    if samples.iter().any(|value| !value.is_finite()) {
        return Err("ICA samples must all be finite.".to_string());
    }
    if requested_components > channel_count {
        return Err("ICA component count cannot exceed the channel count.".to_string());
    }
    if !tolerance.is_finite() || tolerance <= 0.0 || tolerance >= 1.0 {
        return Err("ICA tolerance must be finite and between 0 and 1.".to_string());
    }
    if max_iterations == 0 || max_iterations > 100_000 {
        return Err("ICA maximum iterations must be between 1 and 100000.".to_string());
    }
    Ok(())
}

fn symmetric_decorrelation(matrix: DMatrix<f64>) -> Result<DMatrix<f64>, String> {
    let gram = &matrix * matrix.transpose();
    let eigen = SymmetricEigen::new(gram);
    if eigen
        .eigenvalues
        .iter()
        .any(|value| !value.is_finite() || *value <= f64::EPSILON)
    {
        return Err("ICA decorrelation became singular.".to_string());
    }
    let inverse_root = DMatrix::from_diagonal(&eigen.eigenvalues.map(|value| 1.0 / value.sqrt()));
    Ok(&eigen.eigenvectors * inverse_root * eigen.eigenvectors.transpose() * matrix)
}

fn normalize_components(
    activations: DMatrix<f64>,
    unmixing: DMatrix<f64>,
    mixing: DMatrix<f64>,
) -> (DMatrix<f64>, DMatrix<f64>, DMatrix<f64>, Vec<f64>) {
    let component_count = activations.nrows();
    let sample_count = activations.ncols();
    let raw_energy: Vec<f64> = (0..component_count)
        .map(|component| {
            let activation_variance = activations
                .row(component)
                .iter()
                .map(|value| value * value)
                .sum::<f64>()
                / sample_count as f64;
            let mixing_norm = mixing.column(component).norm_squared();
            activation_variance * mixing_norm
        })
        .collect();
    let mut order: Vec<usize> = (0..component_count).collect();
    order.sort_by(|left, right| raw_energy[*right].total_cmp(&raw_energy[*left]));

    let mut ordered_activations = DMatrix::zeros(component_count, sample_count);
    let mut ordered_unmixing = DMatrix::zeros(component_count, unmixing.ncols());
    let mut ordered_mixing = DMatrix::zeros(mixing.nrows(), component_count);
    let mut energies = Vec::with_capacity(component_count);
    for (new_component, old_component) in order.into_iter().enumerate() {
        let dominant_loading = mixing
            .column(old_component)
            .iter()
            .copied()
            .max_by(|left, right| left.abs().total_cmp(&right.abs()))
            .unwrap_or(1.0);
        let sign = if dominant_loading < 0.0 { -1.0 } else { 1.0 };
        for sample in 0..sample_count {
            ordered_activations[(new_component, sample)] =
                activations[(old_component, sample)] * sign;
        }
        for channel in 0..unmixing.ncols() {
            ordered_unmixing[(new_component, channel)] = unmixing[(old_component, channel)] * sign;
        }
        for channel in 0..mixing.nrows() {
            ordered_mixing[(channel, new_component)] = mixing[(channel, old_component)] * sign;
        }
        energies.push(raw_energy[old_component]);
    }
    let total_energy = energies.iter().sum::<f64>();
    if total_energy > 0.0 {
        for energy in &mut energies {
            *energy /= total_energy;
        }
    }
    (
        ordered_activations,
        ordered_unmixing,
        ordered_mixing,
        energies,
    )
}

fn matrix_rows(matrix: &DMatrix<f64>) -> Vec<Vec<f64>> {
    (0..matrix.nrows())
        .map(|row| matrix.row(row).iter().copied().collect())
        .collect()
}

struct DeterministicRandom {
    state: u64,
}

impl DeterministicRandom {
    fn new(seed: u64) -> Self {
        Self {
            state: seed ^ 0x9E37_79B9_7F4A_7C15,
        }
    }

    fn next_signed(&mut self) -> f64 {
        self.state = self
            .state
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        let unit = (self.state >> 11) as f64 / (1_u64 << 53) as f64;
        2.0 * unit - 1.0
    }
}

#[cfg(test)]
mod tests {
    use super::fast_ica;
    use std::f64::consts::PI;

    #[test]
    fn separates_mixed_independent_sources_and_reconstructs_input() {
        let sample_count = 4096;
        let sources: Vec<Vec<f64>> = vec![
            (0..sample_count)
                .map(|index| (2.0 * PI * 3.0 * index as f64 / 256.0).sin())
                .collect(),
            (0..sample_count)
                .map(|index| {
                    if (2.0 * PI * 5.0 * index as f64 / 256.0).sin() >= 0.0 {
                        1.0
                    } else {
                        -1.0
                    }
                })
                .collect(),
            (0..sample_count)
                .map(|index| ((index * 37 % 101) as f64 - 50.0) / 50.0)
                .collect(),
        ];
        let mixing = [[1.0, 0.5, 0.2], [0.3, 1.2, 0.4], [0.2, 0.1, 0.9]];
        let means = [10.0, -4.0, 2.0];
        let mut mixed = vec![0.0; 3 * sample_count];
        for channel in 0..3 {
            for sample in 0..sample_count {
                mixed[channel * sample_count + sample] = means[channel]
                    + (0..3)
                        .map(|source| mixing[channel][source] * sources[source][sample])
                        .sum::<f64>();
            }
        }

        let result = fast_ica(&mixed, 3, sample_count, 3, 1.0e-5, 500, 42).unwrap();
        assert!(result.converged);
        for source in &sources {
            let best_correlation = result
                .activations
                .iter()
                .map(|activation| correlation(source, activation).abs())
                .fold(0.0, f64::max);
            assert!(
                best_correlation > 0.9,
                "best correlation was {best_correlation}"
            );
        }

        for channel in 0..3 {
            for sample in 0..sample_count {
                let reconstructed = result.channel_means[channel]
                    + (0..3)
                        .map(|component| {
                            result.mixing_matrix[channel][component]
                                * result.activations[component][sample]
                        })
                        .sum::<f64>();
                assert!((reconstructed - mixed[channel * sample_count + sample]).abs() < 1.0e-8);
            }
        }
    }

    #[test]
    fn rejects_rank_deficient_component_requests() {
        let samples: Vec<f64> = (0..2)
            .flat_map(|channel| {
                (0..128).map(move |sample| {
                    let base = sample as f64;
                    if channel == 0 {
                        base
                    } else {
                        base * 2.0
                    }
                })
            })
            .collect();
        let error = fast_ica(&samples, 2, 128, 2, 1.0e-4, 200, 1).unwrap_err();
        assert!(error.contains("linearly independent") || error.contains("numerical rank"));
    }

    fn correlation(left: &[f64], right: &[f64]) -> f64 {
        let left_mean = left.iter().sum::<f64>() / left.len() as f64;
        let right_mean = right.iter().sum::<f64>() / right.len() as f64;
        let numerator = left
            .iter()
            .zip(right)
            .map(|(a, b)| (a - left_mean) * (b - right_mean))
            .sum::<f64>();
        let left_norm = left
            .iter()
            .map(|value| (value - left_mean).powi(2))
            .sum::<f64>()
            .sqrt();
        let right_norm = right
            .iter()
            .map(|value| (value - right_mean).powi(2))
            .sum::<f64>()
            .sqrt();
        numerator / (left_norm * right_norm)
    }
}
