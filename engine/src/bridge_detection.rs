use serde::{Deserialize, Serialize};

const MIN_POSITIVE_METRIC: f64 = 1.0e-300;
const MIN_DISTANCE: f64 = 1.0e-12;
const DISTRIBUTION_BIN_WIDTH: f64 = 0.25;
const INTERPOLATED_BIN_WIDTH: f64 = 0.05;
const PEAK_MAX_ED: f64 = 5.0;
const CUTOFF_MAX_ED: f64 = 10.0;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeDetectionResult {
    pub epoch_sample_count: usize,
    pub interval_sample_count: usize,
    pub epoch_starts: Vec<usize>,
    pub epoch_ends: Vec<usize>,
    /// One upper-triangle vector per epoch. Pair order is (0,1), (0,2), ...,
    /// (0,n-1), (1,2), ... (n-2,n-1).
    pub values: Vec<Vec<f64>>,
    /// Raw temporal variance of each pairwise difference waveform, before any
    /// optional physical-distance normalization or logarithmic transform.
    pub electrical_distances: Vec<Vec<f64>>,
    /// Pair-order flags identifying values normalized by electrode distance.
    pub distance_normalized_pairs: Vec<bool>,
    /// Multiplier used to express raw ED relative to the session median.
    pub electrical_distance_scale: f64,
    /// Cubic-spline-interpolated ED frequency distribution through ED 10.
    pub distribution_electrical_distances: Vec<f64>,
    pub distribution_counts: Vec<f64>,
    pub distribution_peak: Option<f64>,
    pub electrical_distance_cutoff: Option<f64>,
    /// Fraction of epochs at or below the cutoff, in canonical pair order.
    pub pair_below_cutoff_fractions: Vec<f64>,
    pub bridged_pairs: Vec<bool>,
}

pub fn detect_bridges(
    channels: &[Vec<f64>],
    sample_rate: f64,
    epoch_seconds: f64,
    interval_seconds: f64,
    coordinates: &[Option<[f64; 3]>],
) -> Result<BridgeDetectionResult, String> {
    if channels.len() < 2 {
        return Err("Bridge detection requires at least two channels.".into());
    }
    let sample_count = channels.first().map_or(0, Vec::len);
    if sample_count == 0 || channels.iter().any(|channel| channel.len() != sample_count) {
        return Err("Bridge detection requires nonempty equal-length channels.".into());
    }
    if !sample_rate.is_finite() || sample_rate <= 0.0 {
        return Err("Bridge detection requires a positive sample rate.".into());
    }
    if !epoch_seconds.is_finite() || epoch_seconds <= 0.0 {
        return Err("Bridge detection requires a positive epoch length.".into());
    }
    if !interval_seconds.is_finite() || interval_seconds <= 0.0 {
        return Err("Bridge detection requires a positive epoch interval.".into());
    }

    let epoch_sample_count = (epoch_seconds * sample_rate).round().max(1.0) as usize;
    let interval_sample_count = (interval_seconds * sample_rate).round().max(1.0) as usize;
    let pairs = channel_pairs(channels.len());
    let pair_distances: Vec<Option<f64>> = pairs
        .iter()
        .map(|&(first, second)| pair_distance(coordinates, first, second))
        .collect();
    let distance_normalized_pairs = pair_distances
        .iter()
        .map(Option::is_some)
        .collect::<Vec<bool>>();

    let mut epoch_starts = Vec::new();
    let mut epoch_ends = Vec::new();
    let mut values = Vec::new();
    let mut electrical_distances = Vec::new();
    let mut start = 0usize;
    while start
        .checked_add(epoch_sample_count)
        .is_some_and(|end| end <= sample_count)
    {
        let end = start + epoch_sample_count;
        let mut epoch_values = Vec::with_capacity(pairs.len());
        let mut epoch_electrical_distances = Vec::with_capacity(pairs.len());
        for (pair_index, &(first, second)) in pairs.iter().enumerate() {
            let mean_difference = channels[first][start..end]
                .iter()
                .zip(&channels[second][start..end])
                .map(|(left, right)| left - right)
                .sum::<f64>()
                / epoch_sample_count as f64;
            let electrical_distance = channels[first][start..end]
                .iter()
                .zip(&channels[second][start..end])
                .map(|(left, right)| {
                    let centered_difference = (left - right) - mean_difference;
                    centered_difference * centered_difference
                })
                .sum::<f64>()
                / epoch_sample_count as f64;
            let mut score_metric = electrical_distance;
            if let Some(distance) = pair_distances[pair_index] {
                score_metric /= distance;
            }
            epoch_electrical_distances.push(electrical_distance);
            epoch_values.push(-score_metric.max(MIN_POSITIVE_METRIC).ln());
        }
        epoch_starts.push(start);
        epoch_ends.push(end);
        values.push(epoch_values);
        electrical_distances.push(epoch_electrical_distances);
        start = match start.checked_add(interval_sample_count) {
            Some(next) => next,
            None => break,
        };
    }

    let classification = classify_bridges(&electrical_distances, pairs.len());
    Ok(BridgeDetectionResult {
        epoch_sample_count,
        interval_sample_count,
        epoch_starts,
        epoch_ends,
        values,
        electrical_distances,
        distance_normalized_pairs,
        electrical_distance_scale: classification.scale,
        distribution_electrical_distances: classification.distribution_x,
        distribution_counts: classification.distribution_y,
        distribution_peak: classification.peak,
        electrical_distance_cutoff: classification.cutoff,
        pair_below_cutoff_fractions: classification.pair_fractions,
        bridged_pairs: classification.bridged_pairs,
    })
}

struct BridgeClassification {
    scale: f64,
    distribution_x: Vec<f64>,
    distribution_y: Vec<f64>,
    peak: Option<f64>,
    cutoff: Option<f64>,
    pair_fractions: Vec<f64>,
    bridged_pairs: Vec<bool>,
}

fn classify_bridges(electrical_distances: &[Vec<f64>], pair_count: usize) -> BridgeClassification {
    let mut finite_values = electrical_distances
        .iter()
        .flatten()
        .copied()
        .filter(|value| value.is_finite() && *value >= 0.0)
        .collect::<Vec<f64>>();
    finite_values.sort_by(f64::total_cmp);
    let median = median(&finite_values).filter(|value| *value > 0.0);
    let scale = median.map_or(0.0, |value| 100.0 / value);
    let mut pair_fractions = vec![0.0; pair_count];
    let mut bridged_pairs = vec![false; pair_count];
    if scale == 0.0 {
        return BridgeClassification {
            scale,
            distribution_x: Vec::new(),
            distribution_y: Vec::new(),
            peak: None,
            cutoff: None,
            pair_fractions,
            bridged_pairs,
        };
    }

    let bin_count = (CUTOFF_MAX_ED / DISTRIBUTION_BIN_WIDTH).ceil() as usize;
    let mut histogram = vec![0.0; bin_count];
    for value in finite_values {
        let scaled = value * scale;
        if scaled >= 0.0 && scaled < CUTOFF_MAX_ED {
            histogram[(scaled / DISTRIBUTION_BIN_WIDTH).floor() as usize] += 1.0;
        }
    }
    let histogram_x = (0..bin_count)
        .map(|index| (index as f64 + 0.5) * DISTRIBUTION_BIN_WIDTH)
        .collect::<Vec<f64>>();
    let distribution_x = interpolated_axis(
        histogram_x[0],
        *histogram_x.last().unwrap(),
        INTERPOLATED_BIN_WIDTH,
    );
    let distribution_y = natural_cubic_spline(&histogram_x, &histogram, &distribution_x)
        .into_iter()
        .map(|value| value.max(0.0))
        .collect::<Vec<f64>>();
    let peak_index = first_local_peak(&distribution_x, &distribution_y, PEAK_MAX_ED);
    let cutoff_index = peak_index.and_then(|index| {
        first_local_minimum(&distribution_x, &distribution_y, index + 1, CUTOFF_MAX_ED)
    });
    let peak = peak_index.map(|index| distribution_x[index]);
    let cutoff = cutoff_index.map(|index| distribution_x[index]);

    if let Some(cutoff) = cutoff {
        for pair_index in 0..pair_count {
            let mut valid = 0usize;
            let mut below = 0usize;
            for epoch in electrical_distances {
                let Some(value) = epoch.get(pair_index) else {
                    continue;
                };
                if !value.is_finite() || *value < 0.0 {
                    continue;
                }
                valid += 1;
                if *value * scale <= cutoff {
                    below += 1;
                }
            }
            if valid > 0 {
                pair_fractions[pair_index] = below as f64 / valid as f64;
                bridged_pairs[pair_index] = below * 2 >= valid;
            }
        }
    }

    BridgeClassification {
        scale,
        distribution_x,
        distribution_y,
        peak,
        cutoff,
        pair_fractions,
        bridged_pairs,
    }
}

fn median(sorted: &[f64]) -> Option<f64> {
    if sorted.is_empty() {
        return None;
    }
    let middle = sorted.len() / 2;
    Some(if sorted.len().is_multiple_of(2) {
        (sorted[middle - 1] + sorted[middle]) / 2.0
    } else {
        sorted[middle]
    })
}

fn interpolated_axis(start: f64, end: f64, step: f64) -> Vec<f64> {
    let count = ((end - start) / step).floor() as usize;
    (0..=count)
        .map(|index| start + index as f64 * step)
        .collect()
}

fn natural_cubic_spline(x: &[f64], y: &[f64], queries: &[f64]) -> Vec<f64> {
    if x.len() < 3 || x.len() != y.len() {
        return queries.iter().map(|_| 0.0).collect();
    }
    let n = x.len();
    let mut second = vec![0.0; n];
    let mut work = vec![0.0; n - 1];
    for index in 1..(n - 1) {
        let sigma = (x[index] - x[index - 1]) / (x[index + 1] - x[index - 1]);
        let pivot = sigma * second[index - 1] + 2.0;
        second[index] = (sigma - 1.0) / pivot;
        let slope_delta = (y[index + 1] - y[index]) / (x[index + 1] - x[index])
            - (y[index] - y[index - 1]) / (x[index] - x[index - 1]);
        work[index] =
            (6.0 * slope_delta / (x[index + 1] - x[index - 1]) - sigma * work[index - 1]) / pivot;
    }
    for index in (0..(n - 1)).rev() {
        second[index] = second[index] * second[index + 1] + work[index];
    }
    queries
        .iter()
        .map(|query| {
            let upper = x.partition_point(|value| *value < *query).clamp(1, n - 1);
            let lower = upper - 1;
            let width = x[upper] - x[lower];
            let left = (x[upper] - query) / width;
            let right = (query - x[lower]) / width;
            left * y[lower]
                + right * y[upper]
                + ((left.powi(3) - left) * second[lower] + (right.powi(3) - right) * second[upper])
                    * width.powi(2)
                    / 6.0
        })
        .collect()
}

fn first_local_peak(x: &[f64], y: &[f64], maximum_x: f64) -> Option<usize> {
    if y.len() < 2 {
        return None;
    }
    if x[0] <= maximum_x && y[0] > y[1] && y[0] >= 1.0 {
        return Some(0);
    }
    (1..y.len() - 1).find(|index| {
        x[*index] <= maximum_x
            && y[*index] >= 1.0
            && y[*index] > y[*index - 1]
            && y[*index] >= y[*index + 1]
    })
}

fn first_local_minimum(x: &[f64], y: &[f64], start: usize, maximum_x: f64) -> Option<usize> {
    (start.max(1)..y.len().saturating_sub(1)).find(|index| {
        x[*index] <= maximum_x && y[*index] < y[*index - 1] && y[*index] <= y[*index + 1]
    })
}

fn channel_pairs(channel_count: usize) -> Vec<(usize, usize)> {
    let mut pairs = Vec::with_capacity(channel_count.saturating_mul(channel_count - 1) / 2);
    for first in 0..channel_count {
        for second in (first + 1)..channel_count {
            pairs.push((first, second));
        }
    }
    pairs
}

fn pair_distance(coordinates: &[Option<[f64; 3]>], first: usize, second: usize) -> Option<f64> {
    let first = coordinates.get(first).copied().flatten()?;
    let second = coordinates.get(second).copied().flatten()?;
    if first
        .iter()
        .chain(second.iter())
        .any(|value| !value.is_finite())
    {
        return None;
    }
    let distance = ((first[0] - second[0]).powi(2)
        + (first[1] - second[1]).powi(2)
        + (first[2] - second[2]).powi(2))
    .sqrt();
    (distance > MIN_DISTANCE).then_some(distance)
}

#[cfg(test)]
mod tests {
    use super::{classify_bridges, detect_bridges};

    #[test]
    fn computes_negated_log_electrical_distance_in_pair_order() {
        let result = detect_bridges(
            &[
                vec![0.0, 1.0, 2.0, 3.0, 4.0, 5.0],
                vec![0.0, 2.0, 4.0, 6.0, 8.0, 10.0],
                vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
            ],
            2.0,
            2.0,
            1.0,
            &[],
        )
        .unwrap();

        assert_eq!(result.epoch_starts, vec![0, 2]);
        assert_eq!(result.epoch_ends, vec![4, 6]);
        assert_eq!(result.values.len(), 2);
        assert_eq!(result.values[0].len(), 3);
        let expected_01 = -(1.25_f64).ln();
        assert!((result.values[0][0] - expected_01).abs() < 1.0e-12);
        assert!(result.values[0][1] > 600.0);
        assert!((result.electrical_distances[0][0] - 1.25).abs() < 1.0e-12);
        assert_eq!(result.electrical_distances[0][1], 0.0);
    }

    #[test]
    fn normalizes_by_euclidean_distance_when_both_coordinates_exist() {
        let result = detect_bridges(
            &[vec![0.0, 0.0], vec![0.0, 2.0]],
            1.0,
            2.0,
            10.0,
            &[Some([0.0, 0.0, 0.0]), Some([2.0, 0.0, 0.0])],
        )
        .unwrap();

        assert_eq!(result.distance_normalized_pairs, vec![true]);
        assert!((result.electrical_distances[0][0] - 1.0).abs() < 1.0e-12);
        assert!((result.values[0][0] - (2.0_f64).ln()).abs() < 1.0e-12);
    }

    #[test]
    fn constant_pair_offset_does_not_change_electrical_distance() {
        let result = detect_bridges(
            &[vec![1.0, 2.0, 4.0], vec![11.0, 12.0, 14.0]],
            1.0,
            3.0,
            10.0,
            &[],
        )
        .unwrap();

        assert_eq!(result.electrical_distances[0][0], 0.0);
        assert!(result.values[0][0] > 600.0);
    }

    #[test]
    fn identical_channels_produce_a_large_finite_score() {
        let result =
            detect_bridges(&[vec![1.0, 2.0], vec![1.0, 2.0]], 1.0, 2.0, 10.0, &[]).unwrap();

        assert!(result.values[0][0].is_finite());
        assert!(result.values[0][0] > 600.0);
    }

    #[test]
    fn classifies_pairs_seen_below_the_distribution_cutoff_in_half_the_epochs() {
        let epochs = (0..10)
            .map(|index| {
                vec![
                    if index < 6 { 0.01 } else { 1.0 },
                    1.0 + index as f64 * 0.01,
                    1.2 + index as f64 * 0.01,
                ]
            })
            .collect::<Vec<Vec<f64>>>();
        let result = classify_bridges(&epochs, 3);

        assert!(result.peak.is_some());
        assert!(result.cutoff.is_some());
        assert_eq!(result.bridged_pairs, vec![true, false, false]);
        assert!((result.pair_fractions[0] - 0.6).abs() < 1.0e-12);
    }
}
