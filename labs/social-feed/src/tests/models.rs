//! 数据模型单元测试

use chrono::Utc;

use crate::{Moment, UserProfile};

#[test]
fn test_moment_creation() {
    let moment = Moment {
        id: "$evt_1".to_string(),
        author_id: "@alice:example.com".to_string(),
        author_name: "Alice".to_string(),
        author_avatar: None,
        text: "Hello World!".to_string(),
        images: vec![],
        created_at: Utc::now(),
        like_count: 0,
        comment_count: 0,
    };

    assert_eq!(moment.id, "$evt_1");
    assert_eq!(moment.author_id, "@alice:example.com");
    assert_eq!(moment.author_name, "Alice");
    assert_eq!(moment.text, "Hello World!");
}

#[test]
fn test_moment_clone() {
    let moment = Moment {
        id: "$evt_2".to_string(),
        author_id: "@bob:example.com".to_string(),
        author_name: "Bob".to_string(),
        author_avatar: None,
        text: "Test message".to_string(),
        images: vec![],
        created_at: Utc::now(),
        like_count: 0,
        comment_count: 0,
    };

    let cloned = moment.clone();
    assert_eq!(moment.id, cloned.id);
    assert_eq!(moment.author_id, cloned.author_id);
}

#[test]
fn test_user_profile_creation() {
    let profile = UserProfile {
        user_id: "@alice:example.com".to_string(),
        display_name: Some("Alice".to_string()),
        feed_room_id: "!feed_alice:example.com".to_string(),
        avatar_url: None,
        bio: None,
        location: None,
        follower_count: 42,
        following_count: 0,
        moments_count: 0,
    };

    assert_eq!(profile.user_id, "@alice:example.com");
    assert_eq!(profile.display_name.as_deref(), Some("Alice"));
    assert_eq!(profile.feed_room_id, "!feed_alice:example.com");
    assert_eq!(profile.follower_count, 42);
}

#[test]
fn test_user_profile_serialization() {
    let profile = UserProfile {
        user_id: "@alice:example.com".to_string(),
        display_name: Some("Alice".to_string()),
        feed_room_id: "!feed_alice:example.com".to_string(),
        avatar_url: None,
        bio: None,
        location: None,
        follower_count: 10,
        following_count: 0,
        moments_count: 0,
    };

    let json = serde_json::to_string(&profile).expect("Serialization failed");
    let deserialized: UserProfile = serde_json::from_str(&json).expect("Deserialization failed");

    assert_eq!(profile.user_id, deserialized.user_id);
    assert_eq!(profile.display_name, deserialized.display_name);
    assert_eq!(profile.feed_room_id, deserialized.feed_room_id);
    assert_eq!(profile.follower_count, deserialized.follower_count);
}

#[test]
fn test_moment_serialization() {
    let now = Utc::now();
    let moment = Moment {
        id: "$evt_3".to_string(),
        author_id: "@charlie:example.com".to_string(),
        author_name: "Charlie".to_string(),
        author_avatar: None,
        text: "Serialization test".to_string(),
        images: vec![],
        created_at: now,
        like_count: 0,
        comment_count: 0,
    };

    let json = serde_json::to_string(&moment).expect("Serialization failed");
    let deserialized: Moment = serde_json::from_str(&json).expect("Deserialization failed");

    assert_eq!(moment.id, deserialized.id);
    assert_eq!(moment.author_id, deserialized.author_id);
    assert_eq!(moment.text, deserialized.text);
}

#[test]
fn test_moment_timestamp_ordering() {
    let t1 = Utc::now();
    let t2 = t1 + chrono::Duration::seconds(10);
    let t3 = t2 + chrono::Duration::seconds(10);

    let moment1 = Moment {
        id: "$evt_1".to_string(),
        author_id: "@alice:example.com".to_string(),
        author_name: "Alice".to_string(),
        author_avatar: None,
        text: "First".to_string(),
        images: vec![],
        created_at: t1,
        like_count: 0,
        comment_count: 0,
    };

    let moment2 = Moment {
        id: "$evt_2".to_string(),
        author_id: "@alice:example.com".to_string(),
        author_name: "Alice".to_string(),
        author_avatar: None,
        text: "Second".to_string(),
        images: vec![],
        created_at: t2,
        like_count: 0,
        comment_count: 0,
    };

    let moment3 = Moment {
        id: "$evt_3".to_string(),
        author_id: "@alice:example.com".to_string(),
        author_name: "Alice".to_string(),
        author_avatar: None,
        text: "Third".to_string(),
        images: vec![],
        created_at: t3,
        like_count: 0,
        comment_count: 0,
    };

    // Test sorting by timestamp
    let mut moments = vec![moment1, moment2, moment3];
    moments.sort_by(|a, b| b.created_at.cmp(&a.created_at));

    assert_eq!(moments[0].text, "Third");
    assert_eq!(moments[1].text, "Second");
    assert_eq!(moments[2].text, "First");
}

#[test]
fn test_empty_moment_text() {
    let moment = Moment {
        id: "$evt_empty".to_string(),
        author_id: "@alice:example.com".to_string(),
        author_name: "Alice".to_string(),
        author_avatar: None,
        text: String::new(),
        images: vec![],
        created_at: Utc::now(),
        like_count: 0,
        comment_count: 0,
    };

    assert!(moment.text.is_empty());
    assert_eq!(moment.text.len(), 0);
}

#[test]
fn test_zero_followers() {
    let profile = UserProfile {
        user_id: "@newuser:example.com".to_string(),
        display_name: Some("New User".to_string()),
        feed_room_id: "!new_room:example.com".to_string(),
        avatar_url: None,
        bio: None,
        location: None,
        follower_count: 0,
        following_count: 0,
        moments_count: 0,
    };

    assert_eq!(profile.follower_count, 0);
}
