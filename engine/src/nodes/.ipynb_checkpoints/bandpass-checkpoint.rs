use biquad::{Biquad, Coefficients, DirectForm1, Q_BUTTERWORTH_F32, ToHertz, Type};
use crate::types::{SignalData, NodeResult};
use crate::node::Node;
use uuid::Uuid;

pub struct BandpassFilterNode {
    id: String,
    name: String,
    sample_rate: f32,
    low_hz: f32,
    high_hz: f32,
    filter: DirectForm1<f32>,
}

impl BandpassFilterNode {
    pub fn new(name: &str, sample_rate: f32, low_hz: f32, high_hz: f32) -> Self {
        let center_freq: f32 = (low_hz + high_hz) / 2.0;

        // force f32 here explicitly
        let coeffs: Coefficients<f32> = Coefficients::<f32>::from_params(
            Type::BandPass,
            sample_rate.hz(),
            center_freq.hz(),
            Q_BUTTERWORTH_F32,
        ).unwrap();

        // force DirectForm1<f32>
        let filter: DirectForm1<f32> = DirectForm1::<f32>::new(coeffs);

        Self {
            id: Uuid::new_v4().to_string(),
            name: name.to_string(),
            sample_rate,
            low_hz,
            high_hz,
            filter,
        }
    }
}

impl Node for BandpassFilterNode {
    fn id(&self) -> &str { &self.id }
    fn name(&self) -> &str { &self.name }

    fn process(&mut self, input: &SignalData) -> NodeResult {
        let mut filtered = input.clone();
        filtered.samples = input.samples.iter()
            .map(|x| self.filter.run(*x))
            .collect();
        Ok(filtered)
    }
}
