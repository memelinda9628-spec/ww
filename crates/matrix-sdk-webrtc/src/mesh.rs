//! Full-mesh topology manager.
//!
//! For calls with 3–6 participants this module maintains a fully-connected
//! mesh: every participant has a direct peer connection to every other
//! participant.  It tracks per-user [`PeerConnection`]s, handles member
//! join / leave events, and enforces the `max_mesh_participants` limit.
//!
//! [`PeerConnection`]: crate::connection::PeerConnection

use std::collections::HashMap;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Manages the full-mesh topology for a single call.
///
/// Each peer is identified by a Matrix user ID (`String`).  The value is
/// an opaque handle string that the caller maps to a concrete
/// [`PeerConnection`](crate::connection::PeerConnection).  This indirection
/// keeps the mesh module compilable without the `webrtc` feature.
/// Tracks participants in a full-mesh P2P call.
///
/// Maintains a set of user IDs for each call so that
/// the call manager knows which peers to relay ICE
/// candidates and SDP to.
pub struct MeshTopology {
    /// Active peer connections, keyed by Matrix user ID.
    connections: HashMap<String, String>,
    /// Maximum number of participants allowed in this mesh.
    max_participants: usize,
}

impl MeshTopology {
    /// Create a new, empty [`MeshTopology`].
    ///
    /// `max_participants` should typically match
    /// [`CallConfig::max_mesh_participants`](crate::CallConfig::max_mesh_participants).
    pub fn new(max_participants: usize) -> Self {
        Self {
            connections: HashMap::new(),
            max_participants,
        }
    }

    /// Add a peer to the mesh.
    ///
    /// `user_id` is the Matrix user ID (e.g. `@alice:example.org`).
    /// `handle` is an opaque string that the caller uses to look up the
    /// corresponding [`PeerConnection`].
    ///
    /// Returns `Ok(())` on success, or an error if the mesh is full or
    /// the peer is already present.
    pub fn add_peer(
        &mut self,
        user_id: String,
        handle: String,
    ) -> Result<(), MeshError> {
        if self.connections.contains_key(&user_id) {
            return Err(MeshError::PeerAlreadyPresent(user_id));
        }
        if !self.can_add() {
            return Err(MeshError::MeshFull {
                current: self.peer_count(),
                max: self.max_participants,
            });
        }
        self.connections.insert(user_id, handle);
        Ok(())
    }

    /// Remove a peer from the mesh (e.g. on hangup or disconnect).
    ///
    /// Returns the previously-registered handle, if any.
    pub fn remove_peer(&mut self, user_id: &str) -> Option<String> {
        self.connections.remove(user_id)
    }

    /// Return the current number of connected peers.
    pub fn peer_count(&self) -> usize {
        self.connections.len()
    }

    /// Check whether the mesh can accept one more participant.
    pub fn can_add(&self) -> bool {
        self.connections.len() < self.max_participants
    }

    /// Return the maximum number of participants this mesh supports.
    pub fn max_participants(&self) -> usize {
        self.max_participants
    }

    /// Iterate over all registered (user_id, handle) pairs.
    pub fn iter(&self) -> impl Iterator<Item = (&String, &String)> {
        self.connections.iter()
    }

    /// Get the handle for a specific user, if registered.
    pub fn get(&self, user_id: &str) -> Option<&str> {
        self.connections.get(user_id).map(String::as_str)
    }
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn add_and_remove() {
        let mut mesh = MeshTopology::new(6);
        assert_eq!(mesh.peer_count(), 0);
        assert!(mesh.can_add());

        mesh.add_peer("@alice:example.org".into(), "pc_alice".into()).unwrap();
        assert_eq!(mesh.peer_count(), 1);
        assert_eq!(mesh.get("@alice:example.org"), Some("pc_alice"));

        let removed = mesh.remove_peer("@alice:example.org");
        assert_eq!(removed, Some("pc_alice".into()));
        assert_eq!(mesh.peer_count(), 0);
        assert!(mesh.get("@alice:example.org").is_none());
    }

    #[test]
    fn remove_nonexistent() {
        let mut mesh = MeshTopology::new(6);
        assert_eq!(mesh.remove_peer("@ghost:example.org"), None);
    }

    #[test]
    fn duplicate_prevention() {
        let mut mesh = MeshTopology::new(6);
        mesh.add_peer("@alice:example.org".into(), "pc_a".into()).unwrap();
        let err = mesh
            .add_peer("@alice:example.org".into(), "pc_a2".into())
            .unwrap_err();
        assert!(matches!(err, MeshError::PeerAlreadyPresent(_)));
    }

    #[test]
    fn capacity_enforcement() {
        let mut mesh = MeshTopology::new(2);
        mesh.add_peer("@a:example.org".into(), "a".into()).unwrap();
        mesh.add_peer("@b:example.org".into(), "b".into()).unwrap();
        assert!(!mesh.can_add());

        let err = mesh
            .add_peer("@c:example.org".into(), "c".into())
            .unwrap_err();
        match err {
            MeshError::MeshFull { current, max } => {
                assert_eq!(current, 2);
                assert_eq!(max, 2);
            }
            _ => panic!("expected MeshFull, got {:?}", err),
        }
    }

    #[test]
    fn multi_participant_fill_and_iterate() {
        let mut mesh = MeshTopology::new(6);
        let peers = [
            "@alice", "@bob", "@carol",
            "@dave", "@eve", "@frank",
        ];

        for p in &peers {
            let handle = format!("pc_{}", &p[1..]); // strip @
            mesh.add_peer(p.to_string(), handle).unwrap();
        }

        assert_eq!(mesh.peer_count(), 6);
        assert!(!mesh.can_add());
        assert_eq!(mesh.max_participants(), 6);

        // Iterate and verify all present.
        let mut found: Vec<&str> = mesh.iter().map(|(id, _)| id.as_str()).collect();
        found.sort();
        assert_eq!(found, peers);
    }

    #[test]
    fn join_leave_dynamics() {
        let mut mesh = MeshTopology::new(6);

        mesh.add_peer("@alice".into(), "a".into()).unwrap();
        mesh.add_peer("@bob".into(), "b".into()).unwrap();
        mesh.add_peer("@carol".into(), "c".into()).unwrap();
        assert_eq!(mesh.peer_count(), 3);

        // Bob leaves.
        mesh.remove_peer("@bob");
        assert_eq!(mesh.peer_count(), 2);
        assert!(mesh.get("@bob").is_none());
        assert!(mesh.can_add());

        // Bob rejoins.
        mesh.add_peer("@bob".into(), "b2".into()).unwrap();
        assert_eq!(mesh.peer_count(), 3);
        assert_eq!(mesh.get("@bob"), Some("b2"));

        // Remove non-existent (no-op from mesh perspective).
        mesh.remove_peer("@ghost");
        assert_eq!(mesh.peer_count(), 3);
    }
}

/// Errors related to mesh topology management.
#[derive(Debug, thiserror::Error)]
pub enum MeshError {
    /// The mesh has reached its configured participant limit.
    #[error("mesh full: {current}/{max} participants")]
    MeshFull {
        /// Current number of participants.
        current: usize,
        /// Maximum allowed participants.
        max: usize,
    },
    /// The peer is already in the mesh.
    #[error("peer already in mesh: {0}")]
    PeerAlreadyPresent(String),
}
