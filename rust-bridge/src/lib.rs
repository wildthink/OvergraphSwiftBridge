use overgraph::{
    DatabaseEngine, DbOptions, DbStats, Direction, EdgeView, NeighborEntry, NeighborOptions,
    NodeView, PropValue, UpsertEdgeOptions, UpsertNodeOptions,
};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Number, Value};
use std::collections::BTreeMap;
use std::ffi::{c_char, CStr, CString};
use std::path::Path;
use std::ptr;

#[allow(non_camel_case_types)]
pub struct og_db_handle {
    engine: Option<DatabaseEngine>,
}

#[derive(Deserialize)]
struct BridgeRequest {
    method: String,
    params: Value,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct DbOptionsDto {
    create_if_missing: Option<bool>,
    memtable_flush_threshold: Option<usize>,
    edge_uniqueness: Option<bool>,
    compact_after_n_flushes: Option<u32>,
    memtable_hard_cap_bytes: Option<usize>,
    max_immutable_memtables: Option<usize>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct UpsertNodeOptionsDto {
    props: Option<Map<String, Value>>,
    weight: Option<f32>,
    dense_vector: Option<Vec<f32>>,
    sparse_vector: Option<Vec<SparseVectorEntryDto>>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct UpsertEdgeOptionsDto {
    props: Option<Map<String, Value>>,
    weight: Option<f32>,
    valid_from: Option<i64>,
    valid_to: Option<i64>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct NeighborOptionsDto {
    direction: Option<String>,
    edge_label_filter: Option<Vec<String>>,
    limit: Option<usize>,
    at_epoch: Option<i64>,
    decay_lambda: Option<f32>,
}

#[derive(Deserialize, Serialize)]
struct SparseVectorEntryDto {
    dimension: u32,
    value: f32,
}

#[derive(Deserialize)]
struct UpsertNodeParams {
    labels: Vec<String>,
    key: String,
    options: Option<UpsertNodeOptionsDto>,
}

#[derive(Deserialize)]
struct UpsertEdgeParams {
    from: u64,
    to: u64,
    label: String,
    options: Option<UpsertEdgeOptionsDto>,
}

#[derive(Deserialize)]
struct IdParams {
    id: u64,
}

#[derive(Deserialize)]
struct NodeByKeyParams {
    label: String,
    key: String,
}

#[derive(Deserialize)]
struct GetNodesByLabelsParams {
    labels: Vec<String>,
}

#[derive(Deserialize)]
struct NeighborsParams {
    node_id: u64,
    options: Option<NeighborOptionsDto>,
}

#[derive(Serialize)]
struct UInt64Response {
    value: u64,
}

#[derive(Serialize)]
struct NodeEnvelope {
    node: Option<NodeRecordDto>,
}

#[derive(Serialize)]
struct EdgeEnvelope {
    edge: Option<EdgeRecordDto>,
}

#[derive(Serialize)]
struct NodesResponse {
    items: Vec<NodeRecordDto>,
}

#[derive(Serialize)]
struct NeighborsResponse {
    items: Vec<NeighborEntryDto>,
}

#[derive(Serialize)]
struct EmptyResponse {}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct NodeRecordDto {
    id: u64,
    labels: Vec<String>,
    key: String,
    props: Map<String, Value>,
    created_at: i64,
    updated_at: i64,
    weight: f32,
    dense_vector: Option<Vec<f32>>,
    sparse_vector: Option<Vec<SparseVectorEntryDto>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct EdgeRecordDto {
    id: u64,
    from: u64,
    to: u64,
    label: String,
    props: Map<String, Value>,
    created_at: i64,
    updated_at: i64,
    weight: f32,
    valid_from: i64,
    valid_to: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct NeighborEntryDto {
    node_id: u64,
    edge_id: u64,
    label: String,
    weight: f32,
    valid_from: i64,
    valid_to: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DbStatsDto {
    pending_wal_bytes: usize,
    segment_count: usize,
    node_tombstone_count: usize,
    edge_tombstone_count: usize,
    last_compaction_ms: Option<i64>,
    wal_sync_mode: String,
    active_memtable_bytes: usize,
    immutable_memtable_bytes: usize,
    immutable_memtable_count: usize,
    pending_flush_count: usize,
    active_wal_generation_id: u64,
    oldest_retained_wal_generation_id: u64,
}

fn decode_json<T: for<'de> Deserialize<'de>>(value: Value) -> Result<T, String> {
    serde_json::from_value(value).map_err(|error| error.to_string())
}

fn parse_optional_json<T: for<'de> Deserialize<'de> + Default>(input: *const c_char) -> Result<T, String> {
    if input.is_null() {
        return Ok(T::default());
    }
    let value = unsafe { CStr::from_ptr(input) }
        .to_str()
        .map_err(|error| error.to_string())?;
    if value.is_empty() {
        Ok(T::default())
    } else {
        serde_json::from_str(value).map_err(|error| error.to_string())
    }
}

fn json_to_c_string<T: Serialize>(value: &T) -> Result<*mut c_char, String> {
    let json = serde_json::to_string(value).map_err(|error| error.to_string())?;
    CString::new(json)
        .map(CString::into_raw)
        .map_err(|error| error.to_string())
}

fn write_error(error_out: *mut *mut c_char, message: String) {
    if error_out.is_null() {
        return;
    }
    let string = CString::new(message).unwrap_or_else(|_| CString::new("Bridge error").unwrap());
    unsafe {
        *error_out = string.into_raw();
    }
}

fn take_engine<'a>(handle: &'a og_db_handle) -> Result<&'a DatabaseEngine, String> {
    handle
        .engine
        .as_ref()
        .ok_or_else(|| "Database is closed".to_string())
}

fn props_from_json(map: Option<Map<String, Value>>) -> Result<BTreeMap<String, PropValue>, String> {
    map.unwrap_or_default()
        .into_iter()
        .map(|(key, value)| Ok((key, prop_value_from_json(value)?)))
        .collect()
}

fn prop_value_from_json(value: Value) -> Result<PropValue, String> {
    match value {
        Value::Null => Ok(PropValue::Null),
        Value::Bool(value) => Ok(PropValue::Bool(value)),
        Value::Number(value) => {
            if let Some(value) = value.as_i64() {
                Ok(PropValue::Int(value))
            } else if let Some(value) = value.as_u64() {
                Ok(PropValue::UInt(value))
            } else if let Some(value) = value.as_f64() {
                Ok(PropValue::Float(value))
            } else {
                Err("Unsupported JSON number".to_string())
            }
        }
        Value::String(value) => Ok(PropValue::String(value)),
        Value::Array(values) => values
            .into_iter()
            .map(prop_value_from_json)
            .collect::<Result<Vec<_>, _>>()
            .map(PropValue::Array),
        Value::Object(map) => map
            .into_iter()
            .map(|(key, value)| Ok((key, prop_value_from_json(value)?)))
            .collect::<Result<BTreeMap<_, _>, _>>()
            .map(PropValue::Map),
    }
}

fn json_from_prop_value(value: PropValue) -> Value {
    match value {
        PropValue::Null => Value::Null,
        PropValue::Bool(value) => Value::Bool(value),
        PropValue::Int(value) => Value::Number(Number::from(value)),
        PropValue::UInt(value) => Value::Number(Number::from(value)),
        PropValue::Float(value) => Number::from_f64(value)
            .map(Value::Number)
            .unwrap_or(Value::Null),
        PropValue::String(value) => Value::String(value),
        PropValue::Bytes(bytes) => Value::Array(
            bytes
                .into_iter()
                .map(|byte| Value::Number(Number::from(byte)))
                .collect(),
        ),
        PropValue::Array(items) => Value::Array(items.into_iter().map(json_from_prop_value).collect()),
        PropValue::Map(map) => Value::Object(
            map.into_iter()
                .map(|(key, value)| (key, json_from_prop_value(value)))
                .collect(),
        ),
    }
}

fn direction_from_string(value: Option<String>) -> Result<Direction, String> {
    match value.as_deref() {
        None | Some("outgoing") => Ok(Direction::Outgoing),
        Some("incoming") => Ok(Direction::Incoming),
        Some("both") => Ok(Direction::Both),
        Some(other) => Err(format!("Unsupported direction: {other}")),
    }
}

impl From<DbOptionsDto> for DbOptions {
    fn from(value: DbOptionsDto) -> Self {
        let mut options = DbOptions::default();
        if let Some(flag) = value.create_if_missing {
            options.create_if_missing = flag;
        }
        if let Some(threshold) = value.memtable_flush_threshold {
            options.memtable_flush_threshold = threshold;
        }
        if let Some(flag) = value.edge_uniqueness {
            options.edge_uniqueness = flag;
        }
        if let Some(count) = value.compact_after_n_flushes {
            options.compact_after_n_flushes = count;
        }
        if let Some(bytes) = value.memtable_hard_cap_bytes {
            options.memtable_hard_cap_bytes = bytes;
        }
        if let Some(count) = value.max_immutable_memtables {
            options.max_immutable_memtables = count;
        }
        options
    }
}

impl TryFrom<UpsertNodeOptionsDto> for UpsertNodeOptions {
    type Error = String;

    fn try_from(value: UpsertNodeOptionsDto) -> Result<Self, Self::Error> {
        Ok(Self {
            props: props_from_json(value.props)?,
            weight: value.weight.unwrap_or(1.0),
            dense_vector: value.dense_vector,
            sparse_vector: value.sparse_vector.map(|entries| {
                entries
                    .into_iter()
                    .map(|entry| (entry.dimension, entry.value))
                    .collect()
            }),
        })
    }
}

impl TryFrom<UpsertEdgeOptionsDto> for UpsertEdgeOptions {
    type Error = String;

    fn try_from(value: UpsertEdgeOptionsDto) -> Result<Self, Self::Error> {
        Ok(Self {
            props: props_from_json(value.props)?,
            weight: value.weight.unwrap_or(1.0),
            valid_from: value.valid_from,
            valid_to: value.valid_to,
        })
    }
}

impl TryFrom<NeighborOptionsDto> for NeighborOptions {
    type Error = String;

    fn try_from(value: NeighborOptionsDto) -> Result<Self, Self::Error> {
        Ok(Self {
            direction: direction_from_string(value.direction)?,
            edge_label_filter: value.edge_label_filter,
            limit: value.limit,
            at_epoch: value.at_epoch,
            decay_lambda: value.decay_lambda,
        })
    }
}

impl From<NodeView> for NodeRecordDto {
    fn from(value: NodeView) -> Self {
        Self {
            id: value.id,
            labels: value.labels,
            key: value.key,
            props: value
                .props
                .into_iter()
                .map(|(key, value)| (key, json_from_prop_value(value)))
                .collect(),
            created_at: value.created_at,
            updated_at: value.updated_at,
            weight: value.weight,
            dense_vector: value.dense_vector,
            sparse_vector: value.sparse_vector.map(|entries| {
                entries
                    .into_iter()
                    .map(|(dimension, value)| SparseVectorEntryDto { dimension, value })
                    .collect()
            }),
        }
    }
}

impl From<EdgeView> for EdgeRecordDto {
    fn from(value: EdgeView) -> Self {
        Self {
            id: value.id,
            from: value.from,
            to: value.to,
            label: value.label,
            props: value
                .props
                .into_iter()
                .map(|(key, value)| (key, json_from_prop_value(value)))
                .collect(),
            created_at: value.created_at,
            updated_at: value.updated_at,
            weight: value.weight,
            valid_from: value.valid_from,
            valid_to: value.valid_to,
        }
    }
}

impl From<NeighborEntry> for NeighborEntryDto {
    fn from(value: NeighborEntry) -> Self {
        Self {
            node_id: value.node_id,
            edge_id: value.edge_id,
            label: value.label,
            weight: value.weight,
            valid_from: value.valid_from,
            valid_to: value.valid_to,
        }
    }
}

impl From<DbStats> for DbStatsDto {
    fn from(value: DbStats) -> Self {
        Self {
            pending_wal_bytes: value.pending_wal_bytes,
            segment_count: value.segment_count,
            node_tombstone_count: value.node_tombstone_count,
            edge_tombstone_count: value.edge_tombstone_count,
            last_compaction_ms: value.last_compaction_ms,
            wal_sync_mode: value.wal_sync_mode,
            active_memtable_bytes: value.active_memtable_bytes,
            immutable_memtable_bytes: value.immutable_memtable_bytes,
            immutable_memtable_count: value.immutable_memtable_count,
            pending_flush_count: value.pending_flush_count,
            active_wal_generation_id: value.active_wal_generation_id,
            oldest_retained_wal_generation_id: value.oldest_retained_wal_generation_id,
        }
    }
}

fn execute(handle: &mut og_db_handle, request: BridgeRequest) -> Result<*mut c_char, String> {
    let engine = take_engine(handle)?;
    match request.method.as_str() {
        "upsertNode" => {
            let params: UpsertNodeParams = decode_json(request.params)?;
            let options = params.options.unwrap_or_default().try_into()?;
            json_to_c_string(&UInt64Response {
                value: engine.upsert_node(params.labels, &params.key, options).map_err(|e| e.to_string())?,
            })
        }
        "upsertEdge" => {
            let params: UpsertEdgeParams = decode_json(request.params)?;
            let options = params.options.unwrap_or_default().try_into()?;
            json_to_c_string(&UInt64Response {
                value: engine
                    .upsert_edge(params.from, params.to, &params.label, options)
                    .map_err(|e| e.to_string())?,
            })
        }
        "getNode" => {
            let params: IdParams = decode_json(request.params)?;
            json_to_c_string(&NodeEnvelope {
                node: engine
                    .get_node(params.id)
                    .map_err(|e| e.to_string())?
                    .map(NodeRecordDto::from),
            })
        }
        "getEdge" => {
            let params: IdParams = decode_json(request.params)?;
            json_to_c_string(&EdgeEnvelope {
                edge: engine
                    .get_edge(params.id)
                    .map_err(|e| e.to_string())?
                    .map(EdgeRecordDto::from),
            })
        }
        "getNodeByKey" => {
            let params: NodeByKeyParams = decode_json(request.params)?;
            json_to_c_string(&NodeEnvelope {
                node: engine
                    .get_node_by_key(&params.label, &params.key)
                    .map_err(|e| e.to_string())?
                    .map(NodeRecordDto::from),
            })
        }
        "getNodesByLabels" => {
            let params: GetNodesByLabelsParams = decode_json(request.params)?;
            json_to_c_string(&NodesResponse {
                items: engine
                    .get_nodes_by_labels(params.labels)
                    .map_err(|e| e.to_string())?
                    .into_iter()
                    .map(NodeRecordDto::from)
                    .collect(),
            })
        }
        "neighbors" => {
            let params: NeighborsParams = decode_json(request.params)?;
            let options = params.options.unwrap_or_default().try_into()?;
            json_to_c_string(&NeighborsResponse {
                items: engine
                    .neighbors(params.node_id, &options)
                    .map_err(|e| e.to_string())?
                    .into_iter()
                    .map(NeighborEntryDto::from)
                    .collect(),
            })
        }
        "stats" => json_to_c_string(&DbStatsDto::from(engine.stats().map_err(|e| e.to_string())?)),
        "deleteNode" => {
            let params: IdParams = decode_json(request.params)?;
            engine.delete_node(params.id).map_err(|e| e.to_string())?;
            json_to_c_string(&EmptyResponse {})
        }
        "deleteEdge" => {
            let params: IdParams = decode_json(request.params)?;
            engine.delete_edge(params.id).map_err(|e| e.to_string())?;
            json_to_c_string(&EmptyResponse {})
        }
        other => Err(format!("Unsupported method: {other}")),
    }
}

#[no_mangle]
pub extern "C" fn og_db_open(
    path_utf8: *const c_char,
    options_json_utf8: *const c_char,
    error_utf8: *mut *mut c_char,
) -> *mut og_db_handle {
    let result = (|| {
        if path_utf8.is_null() {
            return Err("Database path is required".to_string());
        }
        let path = unsafe { CStr::from_ptr(path_utf8) }
            .to_str()
            .map_err(|error| error.to_string())?;
        let options: DbOptionsDto = parse_optional_json(options_json_utf8)?;
        let engine = DatabaseEngine::open(Path::new(path), &options.into()).map_err(|e| e.to_string())?;
        Ok(Box::into_raw(Box::new(og_db_handle {
            engine: Some(engine),
        })))
    })();
    match result {
        Ok(handle) => handle,
        Err(error) => {
            write_error(error_utf8, error);
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn og_db_close(
    handle: *mut og_db_handle,
    force: bool,
    error_utf8: *mut *mut c_char,
) -> bool {
    let result = (|| {
        let handle = unsafe { handle.as_mut() }.ok_or_else(|| "Database handle is null".to_string())?;
        let engine = handle
            .engine
            .as_ref()
            .ok_or_else(|| "Database is already closed".to_string())?;
        if force {
            engine.close_fast().map_err(|e| e.to_string())?;
        } else {
            engine.close().map_err(|e| e.to_string())?;
        }
        handle.engine = None;
        Ok(())
    })();
    match result {
        Ok(()) => true,
        Err(error) => {
            write_error(error_utf8, error);
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn og_db_call(
    handle: *mut og_db_handle,
    request_json_utf8: *const c_char,
    error_utf8: *mut *mut c_char,
) -> *mut c_char {
    let result = (|| {
        let handle = unsafe { handle.as_mut() }.ok_or_else(|| "Database handle is null".to_string())?;
        if request_json_utf8.is_null() {
            return Err("Request JSON is required".to_string());
        }
        let request = unsafe { CStr::from_ptr(request_json_utf8) }
            .to_str()
            .map_err(|error| error.to_string())?;
        let request: BridgeRequest = serde_json::from_str(request).map_err(|error| error.to_string())?;
        execute(handle, request)
    })();
    match result {
        Ok(response) => response,
        Err(error) => {
            write_error(error_utf8, error);
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn og_db_destroy(handle: *mut og_db_handle) {
    if handle.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub extern "C" fn og_string_free(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(value));
    }
}
