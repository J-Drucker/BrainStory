use std::ffi::{CStr, CString};
use std::fs::{self, File};
use std::io::Write;
use std::os::raw::{c_char, c_int};
use std::path::{Path, PathBuf};
use std::slice;
use std::sync::{Mutex, OnceLock};

use serde_json::{json, Map, Value};
use uuid::Uuid;

#[repr(C)]
struct LibeepTriggerExtension {
    trigger_type: i32,
    code: i32,
    duration_in_samples: u64,
    condition: *const c_char,
    description: *const c_char,
    video_filename: *const c_char,
    impedances: *const c_char,
}

unsafe extern "C" {
    fn libeep_init();
    fn libeep_exit();
    fn libeep_read_with_external_triggers(filename: *const c_char) -> c_int;
    fn libeep_close(handle: c_int);
    fn libeep_get_channel_count(handle: c_int) -> c_int;
    fn libeep_get_channel_label(handle: c_int, index: c_int) -> *const c_char;
    fn libeep_get_sample_frequency(handle: c_int) -> c_int;
    fn libeep_get_sample_count(handle: c_int) -> i64;
    fn libeep_get_samples(handle: c_int, from: i64, to: i64) -> *mut f32;
    fn libeep_free_samples(samples: *mut f32);
    fn libeep_get_trigger_count(handle: c_int) -> c_int;
    fn libeep_get_trigger_with_extensions(
        handle: c_int,
        index: c_int,
        sample: *mut u64,
        extension: *mut LibeepTriggerExtension,
    ) -> *const c_char;
}

static LIBEEP_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

pub fn import(path: &str) -> Result<Value, String> {
    let _guard = LIBEEP_LOCK
        .get_or_init(|| Mutex::new(()))
        .lock()
        .map_err(|_| "LIBEEP import lock was poisoned".to_string())?;
    let file_size = inspect_source_file(path)?;
    let source_path = path.to_string();
    let path = CString::new(path)
        .map_err(|_| format!("The ANT CNT path contains an embedded NUL byte: {source_path:?}"))?;

    unsafe { libeep_init() };
    let handle = unsafe { libeep_read_with_external_triggers(path.as_ptr()) };
    if handle < 0 {
        unsafe { libeep_exit() };
        return Err(format!(
            "LIBEEP rejected the readable ANT CNT file {source_path:?} ({file_size} bytes). The CNT header or internal structure may be unsupported, incomplete, or damaged"
        ));
    }

    let result = read_open_file(handle, path.to_string_lossy().as_ref());
    unsafe {
        libeep_close(handle);
        libeep_exit();
    }
    result
}

fn inspect_source_file(path: &str) -> Result<u64, String> {
    let source = Path::new(path);
    let metadata = fs::metadata(source).map_err(|error| match error.kind() {
        std::io::ErrorKind::NotFound => {
            format!("ANT CNT file was not found at {path:?}")
        }
        std::io::ErrorKind::PermissionDenied => {
            format!("BrainStory does not have permission to access ANT CNT file {path:?}")
        }
        _ => format!("Could not inspect ANT CNT file {path:?}: {error}"),
    })?;
    if !metadata.is_file() {
        return Err(format!("ANT CNT path is not a regular file: {path:?}"));
    }
    if metadata.len() == 0 {
        return Err(format!("ANT CNT file is empty: {path:?} (0 bytes)"));
    }
    File::open(source).map_err(|error| match error.kind() {
        std::io::ErrorKind::PermissionDenied => {
            format!("BrainStory does not have permission to read ANT CNT file {path:?}")
        }
        _ => format!("Could not read ANT CNT file {path:?}: {error}"),
    })?;
    Ok(metadata.len())
}

fn read_open_file(handle: c_int, source_path: &str) -> Result<Value, String> {
    let channel_count = unsafe { libeep_get_channel_count(handle) };
    let sample_rate = unsafe { libeep_get_sample_frequency(handle) };
    let sample_count = unsafe { libeep_get_sample_count(handle) };
    if channel_count <= 0 || sample_rate <= 0 || sample_count <= 0 {
        return Err(
            "The CNT file does not contain usable channel or sampling information".to_string(),
        );
    }
    let channel_count = channel_count as usize;
    let sample_count = usize::try_from(sample_count)
        .map_err(|_| "The CNT file has an unsupported sample count".to_string())?;
    let value_count = channel_count
        .checked_mul(sample_count)
        .ok_or_else(|| "The CNT sample array is too large".to_string())?;

    let labels = (0..channel_count)
        .map(|index| unsafe { string_from_ptr(libeep_get_channel_label(handle, index as c_int)) })
        .map(|label| label.unwrap_or_else(|| "Unnamed channel".to_string()))
        .collect::<Vec<_>>();
    let samples = unsafe { libeep_get_samples(handle, 0, sample_count as i64) };
    if samples.is_null() {
        return Err("LIBEEP could not decode CNT samples".to_string());
    }

    let output_dir = std::env::temp_dir().join(format!("brainstory_ant_cnt_{}", Uuid::new_v4()));
    let write_result = (|| -> Result<PathBuf, String> {
        fs::create_dir(&output_dir)
            .map_err(|error| format!("Could not create temporary import storage: {error}"))?;
        let samples_path = output_dir.join("samples.f32");
        let mut output = File::create(&samples_path)
            .map_err(|error| format!("Could not create the imported sample file: {error}"))?;
        let muxed = unsafe { slice::from_raw_parts(samples, value_count) };
        for channel_index in 0..channel_count {
            for sample_index in 0..sample_count {
                output
                    .write_all(&muxed[sample_index * channel_count + channel_index].to_le_bytes())
                    .map_err(|error| format!("Could not write imported samples: {error}"))?;
            }
        }
        Ok(samples_path)
    })();
    unsafe { libeep_free_samples(samples) };
    let samples_path = match write_result {
        Ok(path) => path,
        Err(error) => {
            let _ = fs::remove_dir_all(&output_dir);
            return Err(error);
        }
    };

    let (markers, impedance) = read_events(handle, sample_rate as f64, &labels);
    Ok(json!({
        "sourceDescription": source_path,
        "sampleRate": sample_rate,
        "channelLabels": labels,
        "channelCount": channel_count,
        "sampleCount": sample_count,
        "units": "uV",
        "samplesFile": samples_path,
        "tempDir": output_dir,
        "markers": markers,
        "impedance": impedance,
    }))
}

fn read_events(handle: c_int, sample_rate: f64, labels: &[String]) -> (Vec<Value>, Value) {
    let trigger_count = unsafe { libeep_get_trigger_count(handle) }.max(0) as usize;
    let mut markers = Vec::new();
    let mut measurement_times_micros = Vec::new();
    let mut ohms_by_channel = vec![Vec::<Option<f64>>::new(); labels.len()];
    for index in 0..trigger_count {
        let marker = unsafe {
            let mut sample = 0_u64;
            let mut extension: LibeepTriggerExtension = std::mem::zeroed();
            let Some(label) = string_from_ptr(libeep_get_trigger_with_extensions(
                handle,
                index as c_int,
                &mut sample,
                &mut extension,
            )) else {
                continue;
            };
            let description = string_from_ptr(extension.description).unwrap_or_default();
            let condition = string_from_ptr(extension.condition).unwrap_or_default();
            let duration_micros =
                ((extension.duration_in_samples as f64 / sample_rate) * 1_000_000.0).round() as u64;
            let onset_micros = ((sample as f64 / sample_rate) * 1_000_000.0).round() as u64;
            let is_impedance =
                description.eq_ignore_ascii_case("impedance") && !extension.impedances.is_null();
            if is_impedance {
                measurement_times_micros.push(onset_micros);
                let readings =
                    parse_impedance_values(string_from_ptr(extension.impedances).as_deref());
                for (channel_index, row) in ohms_by_channel.iter_mut().enumerate() {
                    row.push(readings.get(channel_index).copied().flatten());
                }
                continue;
            }
            let mut attributes = Map::new();
            attributes.insert("source".to_string(), Value::String("ANT CNT".to_string()));
            attributes.insert(
                "ant.triggerType".to_string(),
                Value::from(extension.trigger_type),
            );
            attributes.insert("ant.triggerCode".to_string(), Value::from(extension.code));
            if !description.is_empty() {
                attributes.insert(
                    "ant.description".to_string(),
                    Value::String(description.clone()),
                );
            }
            if !condition.is_empty() {
                attributes.insert("ant.condition".to_string(), Value::String(condition));
            }
            json!({
                "label": label,
                "onsetMicros": onset_micros,
                "durationMicros": duration_micros,
                "markerType": marker_type(&label, &description, duration_micros),
                "attributes": attributes,
            })
        };
        markers.push(marker);
    }
    let impedance = if measurement_times_micros.is_empty() {
        Value::Null
    } else {
        json!({
            "channelLabels": labels,
            "measurementTimesMicros": measurement_times_micros,
            "ohmsByChannel": ohms_by_channel,
        })
    };
    (markers, impedance)
}

fn parse_impedance_values(raw: Option<&str>) -> Vec<Option<f64>> {
    raw.unwrap_or_default()
        .split_whitespace()
        .map(|value| value.parse::<f64>().ok())
        .collect()
}

fn marker_type(label: &str, description: &str, duration_micros: u64) -> &'static str {
    let lower = format!("{label} {description}").to_ascii_lowercase();
    if lower.contains("bad") || lower.contains("artifact") {
        "artifact"
    } else if duration_micros == 0 {
        "event"
    } else {
        "window"
    }
}

unsafe fn string_from_ptr(pointer: *const c_char) -> Option<String> {
    if pointer.is_null() {
        None
    } else {
        Some(CStr::from_ptr(pointer).to_string_lossy().into_owned())
    }
}

#[no_mangle]
pub extern "C" fn brainstory_ant_cnt_import(path: *const c_char) -> *mut c_char {
    let result = unsafe {
        if path.is_null() {
            Err("ANT CNT import did not receive a file path".to_string())
        } else {
            match CStr::from_ptr(path).to_str() {
                Ok(path) => import(path),
                Err(_) => Err("The CNT path is not valid UTF-8".to_string()),
            }
        }
    };
    let payload = match result {
        Ok(payload) => json!({"ok": true, "payload": payload}),
        Err(error) => json!({"ok": false, "error": error}),
    };
    CString::new(payload.to_string())
        .expect("JSON cannot contain NUL bytes")
        .into_raw()
}

#[no_mangle]
pub extern "C" fn brainstory_engine_free_string(pointer: *mut c_char) {
    if !pointer.is_null() {
        unsafe { drop(CString::from_raw(pointer)) };
    }
}

#[cfg(test)]
mod tests {
    use super::inspect_source_file;
    use std::fs;

    use uuid::Uuid;

    #[test]
    fn reports_missing_cnt_path() {
        let path = std::env::temp_dir().join(format!("missing-{}.cnt", Uuid::new_v4()));
        let error = inspect_source_file(path.to_string_lossy().as_ref()).unwrap_err();
        assert!(error.contains("was not found"));
        assert!(error.contains(path.to_string_lossy().as_ref()));
    }

    #[test]
    fn reports_empty_cnt_file() {
        let path = std::env::temp_dir().join(format!("empty-{}.cnt", Uuid::new_v4()));
        fs::write(&path, []).unwrap();
        let error = inspect_source_file(path.to_string_lossy().as_ref()).unwrap_err();
        let _ = fs::remove_file(&path);
        assert!(error.contains("is empty"));
        assert!(error.contains("0 bytes"));
    }

    #[test]
    fn reports_readable_cnt_file_size() {
        let path = std::env::temp_dir().join(format!("readable-{}.cnt", Uuid::new_v4()));
        fs::write(&path, [1_u8, 2, 3, 4]).unwrap();
        let size = inspect_source_file(path.to_string_lossy().as_ref()).unwrap();
        let _ = fs::remove_file(&path);
        assert_eq!(size, 4);
    }
}
