//! 交互功能模块 [like / comment / forward，联动 rate_limit + aggregation]
//!
//! 包含点赞、评论、转发等用户交互功能。

use matrix_sdk::ruma::{
    events::{
        reaction::ReactionEventContent, relation::Annotation,
        room::message::RoomMessageEventContent,
    },
    OwnedEventId,
};
use matrix_sdk_ui::timeline::RoomExt;

use super::feed::SocialFeed;
use crate::{
    services::{quote_forward::ForwardMetadata, rate_limit::OperationType},
    types::{
        error::{Result, SocialFeedError},
        models::Moment,
    },
};

impl SocialFeed {
    /// 点赞
    pub async fn like(&self, room_id: &str, event_id: &str) -> Result<()> {
        self.rate_limiter.wait_until_allowed(OperationType::Like).await;
        let room = self.get_room(room_id)?;
        let eid: OwnedEventId = event_id
            .try_into()
            .map_err(|_| SocialFeedError::InvalidEventId(event_id.to_string()))?;

        room.send(ReactionEventContent::new(Annotation::new(eid, "👍".to_owned())))
            .await
            .map_err(|e| SocialFeedError::SdkError(e.to_string()))?;

        // 联动：更新聚合计数
        self.aggregation_cache.increment_likes(room_id, event_id).await;
        Ok(())
    }

    /// 评论（回复某条动态）
    pub async fn comment(&self, room_id: &str, event_id: &str, text: &str) -> Result<()> {
        self.rate_limiter.wait_until_allowed(OperationType::Comment).await;
        let room = self.get_room(room_id)?;
        let eid: OwnedEventId = event_id
            .try_into()
            .map_err(|_| SocialFeedError::InvalidEventId(event_id.to_string()))?;

        let timeline =
            room.timeline().await.map_err(|e| SocialFeedError::SdkError(e.to_string()))?;

        timeline
            .send_reply(RoomMessageEventContent::text_plain(text).into(), eid)
            .await
            .map_err(|e| SocialFeedError::SdkError(e.to_string()))?;

        // 联动：更新聚合计数
        self.aggregation_cache.increment_replies(room_id, event_id).await;
        Ok(())
    }

    /// 转发（引用原动态并附言发到自己主页）。
    ///
    /// 使用 ForwardMetadata 生成带原文 blockquote + 附言的富文本转发消息，
    /// 支持跨 homeserver：原文信息以 JSON 嵌入消息体作为 fallback。
    ///
    /// # 参数
    /// - `source_room_id`：原始动态所在的 Room ID
    /// - `original_moment`：原始动态的 Moment 对象（提供作者/原文/头像等）
    /// - `quote_text`：转发者的附言
    pub async fn forward(
        &self,
        source_room_id: &str,
        original_moment: &Moment,
        quote_text: &str,
    ) -> Result<()> {
        self.rate_limiter.wait_until_allowed(OperationType::Forward).await;

        let eid: OwnedEventId = original_moment
            .id
            .as_str()
            .try_into()
            .map_err(|_| SocialFeedError::InvalidEventId(original_moment.id.clone()))?;

        let event_url =
            format!("matrix://roomid/{}/eventid/{}", source_room_id, original_moment.id);

        // 构造带原文的转发元数据
        let metadata = ForwardMetadata::from_moment(
            original_moment,
            source_room_id.to_string(),
            quote_text.to_string(),
            event_url,
        );

        let my_room = self.get_my_room()?;
        let my_timeline =
            my_room.timeline().await.map_err(|e| SocialFeedError::SdkError(e.to_string()))?;

        // 发送 HTML + 纯文本双格式转发消息
        my_timeline
            .send_reply(
                RoomMessageEventContent::text_html(
                    metadata.plain_body(),
                    metadata.formatted_body(),
                )
                .into(),
                eid,
            )
            .await
            .map_err(|e| SocialFeedError::SdkError(e.to_string()))?;

        // 联动：更新源事件的转发计数
        self.aggregation_cache.increment_forwards(source_room_id, &original_moment.id).await;
        Ok(())
    }
}
