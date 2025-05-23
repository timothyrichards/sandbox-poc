use crate::types::DbVector3;
use spacetimedb::{Identity, ReducerContext, Table};

#[spacetimedb::table(name = creative_camera, public)]
pub struct CreativeCamera {
    #[primary_key]
    pub identity: Identity,
    pub enabled: bool,
    pub position: DbVector3,
    pub rotation: DbVector3,
}

pub fn creative_camera_create(ctx: &ReducerContext) -> Result<(), String> {
    let creative_camera = CreativeCamera {
        identity: ctx.sender,
        enabled: false,
        position: DbVector3::default(),
        rotation: DbVector3::default(),
    };
    ctx.db.creative_camera().insert(creative_camera);
    Ok(())
}

#[spacetimedb::reducer]
pub fn creative_camera_set_enabled(ctx: &ReducerContext, enabled: bool) -> Result<(), String> {
    if let Some(mut creative_camera) = ctx.db.creative_camera().identity().find(ctx.sender) {
        creative_camera.enabled = enabled;
        ctx.db.creative_camera().identity().update(creative_camera);
    }
    Ok(())
}

#[spacetimedb::reducer]
pub fn creative_camera_move(
    ctx: &ReducerContext,
    position: DbVector3,
    rotation: DbVector3,
) -> Result<(), String> {
    if let Some(mut creative_camera) = ctx.db.creative_camera().identity().find(ctx.sender) {
        creative_camera.position = position;
        creative_camera.rotation = rotation;
        ctx.db.creative_camera().identity().update(creative_camera);
        Ok(())
    } else {
        Err("Creative camera not found".to_string())
    }
}
