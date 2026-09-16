use serde::Serialize;
use std::f64::consts::PI;

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GaussianMixtureResult {
    pub assignments: Vec<usize>,
    pub probabilities: Vec<Vec<f64>>,
    pub weights: Vec<f64>,
    pub means: Vec<Vec<f64>>,
    pub variances: Vec<Vec<f64>>,
    pub converged: bool,
    pub iteration_count: usize,
    pub log_likelihood: f64,
    pub aic: f64,
    pub bic: f64,
    pub normalization_mean: Vec<f64>,
    pub normalization_scale: Vec<f64>,
}

pub fn fit_gaussian_mixture(
    rows: &[Vec<f64>],
    component_count: usize,
    tolerance: f64,
    max_iterations: usize,
    regularization: f64,
    standardize: bool,
    seed: u64,
) -> Option<GaussianMixtureResult> {
    let row_count = rows.len();
    let feature_count = rows.first()?.len();
    if feature_count == 0
        || component_count == 0
        || component_count > 32
        || row_count < component_count
        || rows
            .iter()
            .any(|row| row.len() != feature_count || row.iter().any(|value| !value.is_finite()))
        || !tolerance.is_finite()
        || tolerance <= 0.0
        || max_iterations == 0
        || max_iterations > 10_000
        || !regularization.is_finite()
        || regularization <= 0.0
    {
        return None;
    }

    let normalization_mean: Vec<f64> = (0..feature_count)
        .map(|feature| rows.iter().map(|row| row[feature]).sum::<f64>() / row_count as f64)
        .collect();
    let normalization_scale: Vec<f64> = (0..feature_count)
        .map(|feature| {
            if !standardize {
                return 1.0;
            }
            let variance = rows
                .iter()
                .map(|row| (row[feature] - normalization_mean[feature]).powi(2))
                .sum::<f64>()
                / row_count as f64;
            let scale = variance.sqrt();
            if scale > 1.0e-12 {
                scale
            } else {
                1.0
            }
        })
        .collect();
    let normalized: Vec<Vec<f64>> = rows
        .iter()
        .map(|row| {
            (0..feature_count)
                .map(|feature| {
                    (row[feature] - normalization_mean[feature]) / normalization_scale[feature]
                })
                .collect()
        })
        .collect();

    let mut rng = DeterministicRng::new(seed);
    let mut means = initialize_means(&normalized, component_count, &mut rng);
    let global_variance: Vec<f64> = (0..feature_count)
        .map(|feature| {
            normalized
                .iter()
                .map(|row| row[feature] * row[feature])
                .sum::<f64>()
                / row_count as f64
                + regularization
        })
        .collect();
    let mut variances = vec![global_variance.clone(); component_count];
    let mut weights = vec![1.0 / component_count as f64; component_count];
    let mut probabilities = vec![vec![0.0; component_count]; row_count];
    let mut previous_log_likelihood = f64::NEG_INFINITY;
    let mut converged = false;
    let mut iteration_count = 0;

    for iteration in 0..max_iterations {
        let log_likelihood = expectation(
            &normalized,
            &weights,
            &means,
            &variances,
            &mut probabilities,
        );
        iteration_count = iteration + 1;
        if iteration > 0
            && (log_likelihood - previous_log_likelihood).abs()
                <= tolerance * (1.0 + previous_log_likelihood.abs())
        {
            converged = true;
            break;
        }
        previous_log_likelihood = log_likelihood;
        maximize(
            &normalized,
            &probabilities,
            &global_variance,
            regularization,
            &mut weights,
            &mut means,
            &mut variances,
            &mut rng,
        );
    }

    // Return responsibilities for the final model, including when the final
    // maximization step reached the iteration limit.
    let log_likelihood = expectation(
        &normalized,
        &weights,
        &means,
        &variances,
        &mut probabilities,
    );
    let assignments = probabilities
        .iter()
        .map(|row| {
            row.iter()
                .enumerate()
                .max_by(|left, right| left.1.total_cmp(right.1))
                .map(|(index, _)| index)
                .unwrap_or(0)
        })
        .collect();
    let parameter_count = (component_count - 1) + (2 * component_count * feature_count);
    let means_original = means
        .iter()
        .map(|component| {
            (0..feature_count)
                .map(|feature| {
                    component[feature] * normalization_scale[feature] + normalization_mean[feature]
                })
                .collect()
        })
        .collect();
    let variances_original = variances
        .iter()
        .map(|component| {
            (0..feature_count)
                .map(|feature| component[feature] * normalization_scale[feature].powi(2))
                .collect()
        })
        .collect();

    Some(GaussianMixtureResult {
        assignments,
        probabilities,
        weights,
        means: means_original,
        variances: variances_original,
        converged,
        iteration_count,
        log_likelihood,
        aic: 2.0 * parameter_count as f64 - 2.0 * log_likelihood,
        bic: (parameter_count as f64) * (row_count as f64).ln() - 2.0 * log_likelihood,
        normalization_mean,
        normalization_scale,
    })
}

fn expectation(
    rows: &[Vec<f64>],
    weights: &[f64],
    means: &[Vec<f64>],
    variances: &[Vec<f64>],
    probabilities: &mut [Vec<f64>],
) -> f64 {
    let mut total = 0.0;
    for (row_index, row) in rows.iter().enumerate() {
        let mut log_probabilities = Vec::with_capacity(weights.len());
        for component in 0..weights.len() {
            let mut value = weights[component].max(1.0e-300).ln();
            for feature in 0..row.len() {
                let variance = variances[component][feature];
                let delta = row[feature] - means[component][feature];
                value += -0.5 * ((2.0 * PI * variance).ln() + delta * delta / variance);
            }
            log_probabilities.push(value);
        }
        let maximum = log_probabilities
            .iter()
            .copied()
            .fold(f64::NEG_INFINITY, f64::max);
        let denominator: f64 = log_probabilities
            .iter()
            .map(|value| (value - maximum).exp())
            .sum();
        let log_normalizer = maximum + denominator.ln();
        total += log_normalizer;
        for (component, value) in log_probabilities.iter().enumerate() {
            probabilities[row_index][component] = (value - log_normalizer).exp();
        }
    }
    total
}

#[allow(clippy::too_many_arguments)]
fn maximize(
    rows: &[Vec<f64>],
    probabilities: &[Vec<f64>],
    global_variance: &[f64],
    regularization: f64,
    weights: &mut [f64],
    means: &mut [Vec<f64>],
    variances: &mut [Vec<f64>],
    rng: &mut DeterministicRng,
) {
    let row_count = rows.len();
    let feature_count = rows[0].len();
    let mut effective_counts = vec![0.0; weights.len()];
    for row in probabilities {
        for (component, value) in row.iter().enumerate() {
            effective_counts[component] += value;
        }
    }
    for component in 0..weights.len() {
        let count = effective_counts[component];
        if count <= 1.0e-8 {
            means[component] = rows[rng.index(row_count)].clone();
            variances[component] = global_variance.to_vec();
            weights[component] = 1.0 / row_count as f64;
            continue;
        }
        for feature in 0..feature_count {
            means[component][feature] = rows
                .iter()
                .enumerate()
                .map(|(row_index, row)| probabilities[row_index][component] * row[feature])
                .sum::<f64>()
                / count;
        }
        for feature in 0..feature_count {
            variances[component][feature] = rows
                .iter()
                .enumerate()
                .map(|(row_index, row)| {
                    let delta = row[feature] - means[component][feature];
                    probabilities[row_index][component] * delta * delta
                })
                .sum::<f64>()
                / count
                + regularization;
        }
        weights[component] = count / row_count as f64;
    }
    let weight_sum: f64 = weights.iter().sum();
    for weight in weights {
        *weight /= weight_sum;
    }
}

fn initialize_means(
    rows: &[Vec<f64>],
    component_count: usize,
    rng: &mut DeterministicRng,
) -> Vec<Vec<f64>> {
    let mut means = vec![rows[rng.index(rows.len())].clone()];
    while means.len() < component_count {
        let distances: Vec<f64> = rows
            .iter()
            .map(|row| {
                means
                    .iter()
                    .map(|mean| squared_distance(row, mean))
                    .fold(f64::INFINITY, f64::min)
            })
            .collect();
        let total: f64 = distances.iter().sum();
        let index = if total <= 1.0e-12 {
            means.len() % rows.len()
        } else {
            let target = rng.unit() * total;
            let mut cumulative = 0.0;
            distances
                .iter()
                .position(|distance| {
                    cumulative += distance;
                    cumulative >= target
                })
                .unwrap_or(rows.len() - 1)
        };
        means.push(rows[index].clone());
    }
    means
}

fn squared_distance(left: &[f64], right: &[f64]) -> f64 {
    left.iter().zip(right).map(|(a, b)| (a - b).powi(2)).sum()
}

struct DeterministicRng(u64);

impl DeterministicRng {
    fn new(seed: u64) -> Self {
        Self(seed.max(1))
    }

    fn next(&mut self) -> u64 {
        let mut value = self.0;
        value ^= value << 13;
        value ^= value >> 7;
        value ^= value << 17;
        self.0 = value;
        value
    }

    fn unit(&mut self) -> f64 {
        self.next() as f64 / u64::MAX as f64
    }

    fn index(&mut self, length: usize) -> usize {
        (self.next() as usize) % length
    }
}

#[cfg(test)]
mod tests {
    use super::fit_gaussian_mixture;

    #[test]
    fn separates_two_well_spaced_groups() {
        let rows: Vec<Vec<f64>> = (0..40)
            .map(|index| {
                let offset = (index % 10) as f64 * 0.02;
                if index < 20 {
                    vec![-3.0 + offset, -2.0 - offset]
                } else {
                    vec![4.0 + offset, 5.0 - offset]
                }
            })
            .collect();
        let result =
            fit_gaussian_mixture(&rows, 2, 1.0e-6, 200, 1.0e-6, true, 42).expect("valid mixture");

        assert!(result.converged);
        assert_eq!(result.probabilities.len(), rows.len());
        assert_ne!(result.assignments[0], result.assignments[39]);
        assert!(result.probabilities.iter().all(|row| {
            (row.iter().sum::<f64>() - 1.0).abs() < 1.0e-9
                && row.iter().copied().fold(0.0, f64::max) > 0.99
        }));
    }

    #[test]
    fn rejects_more_components_than_rows() {
        assert!(
            fit_gaussian_mixture(&[vec![1.0], vec![2.0]], 3, 1.0e-4, 100, 1.0e-6, true, 42,)
                .is_none()
        );
    }
}
