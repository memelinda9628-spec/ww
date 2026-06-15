//! Social Feed Lab → UniFFI bridge

use crate::ClientError;
use matrix_sdk::Account;
use matrix_sdk::ruma::{
    UserId,
    api::client::profile::{AvatarUrl, DisplayName},
    api::client::user_directory::search_users,
};

/// 用户资料（UniFFI 导出版，9 字段）
#[derive(uniffi::Record)]
pub struct UserProfile {
    pub user_id: String,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    pub bio: Option<String>,
    pub location: Option<String>,
    pub feed_room_id: String,
    pub follower_count: u64,
    pub following_count: u64,
    pub moments_count: u64,
}

impl UserProfile {
    /// 通过 Matrix profile API 查询用户资料。
    /// 额外 6 字段（bio/location/feed_room_id/计数）用默认值。
    pub async fn fetch(account: &Account, user_id: &UserId) -> Result<Self, ClientError> {
        fetch_user_profile(account, user_id).await
    }
}

impl From<&social_feed::types::models::UserProfile> for UserProfile {
    fn from(p: &social_feed::types::models::UserProfile) -> Self {
        UserProfile {
            user_id: p.user_id.clone(),
            display_name: p.display_name.clone(),
            avatar_url: p.avatar_url.clone(),
            bio: p.bio.clone(),
            location: p.location.clone(),
            feed_room_id: p.feed_room_id.clone(),
            follower_count: p.follower_count,
            following_count: p.following_count,
            moments_count: p.moments_count,
        }
    }
}

impl From<&search_users::v3::User> for UserProfile {
    fn from(value: &search_users::v3::User) -> Self {
        UserProfile {
            user_id: value.user_id.to_string(),
            display_name: value.display_name.clone(),
            avatar_url: value.avatar_url.as_ref().map(|url| url.to_string()),
            bio: None,
            location: None,
            feed_room_id: String::new(),
            follower_count: 0,
            following_count: 0,
            moments_count: 0,
        }
    }
}

/// 桥接：用 Matrix profile API 填充 UserProfile。
/// 额外 6 字段用默认值。完整资料需通过 SocialFeed 获取。
pub(crate) async fn fetch_user_profile(
    account: &Account,
    user_id: &UserId,
) -> Result<UserProfile, ClientError> {
    let response = account.fetch_user_profile_of(user_id).await?;
    let display_name = response.get_static::<DisplayName>()?;
    let avatar_url = response.get_static::<AvatarUrl>()?.map(|u| u.to_string());

    Ok(UserProfile {
        user_id: user_id.to_string(),
        display_name,
        avatar_url,
        bio: None,
        location: None,
        feed_room_id: String::new(),
        follower_count: 0,
        following_count: 0,
        moments_count: 0,
    })
}
