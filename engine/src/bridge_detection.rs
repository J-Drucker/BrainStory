use serde::{Deserialize, Serialize};

const MIN_POSITIVE_METRIC: f64 = 1.0e-300;
const MIN_DISTANCE: f64 = 1.0e-12;

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

    Ok(BridgeDetectionResult {
        epoch_sample_count,
        interval_sample_count,
        epoch_starts,
        epoch_ends,
        values,
        electrical_distances,
        distance_normalized_pairs,
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
    use super::detect_bridges;

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
}
