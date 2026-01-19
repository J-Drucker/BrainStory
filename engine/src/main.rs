mod node;
mod pipeline;
mod types;
mod nodes;

use crate::node::Node;
use nodes::bandpass::BandpassFilterNode;

fn main() {
    println!("BrainStory Engine initialized.");

    let mut node = BandpassFilterNode::new("Filter1", 250.0, 1.0, 40.0);
    let input = crate::types::SignalData {
        samples: vec![0.1, 0.2, 0.3, 0.2, 0.1],
        sample_rate: 250.0,
        num_channels: 1,
    };

    let output = node.process(&input).unwrap();
    println!("Filtered: {:?}", output.samples);
}
