use anyhow::Result;

#[derive(Debug, Clone)]
pub struct SignalData {
    pub samples: Vec<f32>,
    pub sample_rate: f32,
    pub num_channels: usize,
}

pub type NodeResult = Result<SignalData>;
