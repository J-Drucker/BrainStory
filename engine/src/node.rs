use crate::types::{SignalData, NodeResult};

pub trait Node {
    fn id(&self) -> &str;
    fn name(&self) -> &str;
    fn process(&mut self, input: &SignalData) -> NodeResult;
}
