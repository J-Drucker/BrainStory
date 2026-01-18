use crate::node::Node;
use crate::types::{SignalData, NodeResult};
use std::collections::HashMap;

pub struct Pipeline {
    nodes: HashMap<String, Box<dyn Node>>,
    execution_order: Vec<String>,
}

impl Pipeline {
    pub fn new() -> Self {
        Self {
            nodes: HashMap::new(),
            execution_order: Vec::new(),
        }
    }

    pub fn add_node(&mut self, id: String, node: Box<dyn Node>) {
        self.execution_order.push(id.clone());
        self.nodes.insert(id, node);
    }

    pub fn run(&mut self, input: SignalData) {
        let mut data = input;
        for node_id in &self.execution_order {
            if let Some(node) = self.nodes.get_mut(node_id) {
                match node.process(&data) {
                    Ok(output) => data = output,
                    Err(e) => {
                        eprintln!("Node {} failed: {}", node.name(), e);
                        break;
                    }
                }
            }
        }
    }
}
