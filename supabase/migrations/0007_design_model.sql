-- 0007_design_model.sql
-- Designer role support:
--  • design_versions.model_url  — the approved 3D model (.glb) shown in the app
--    (client My Trucks card + admin/PM project detail). file_url stays the 2D
--    image/preview; model_url is specifically the glTF-Binary model.
--  • design_artifacts.client_feedback — the note a client leaves when they tap
--    "Request changes", so the designer knows exactly what to fix.

alter table design_versions  add column if not exists model_url      text;
alter table design_artifacts add column if not exists client_feedback text;
