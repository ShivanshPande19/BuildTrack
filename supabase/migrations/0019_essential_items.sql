-- 0019_essential_items.sql
--
-- Separate "who orders this item" from "how it is tracked".
--
-- Two independent facts about a catalogue item:
--   • serialized  — HOW it is tracked (per-unit component vs bulk quantity).
--   • is_essential — WHO orders it:
--       - Project-specific items (LED screen, a truck's BOM parts) come from the
--         PM: they land as procurement_requirements and procurement orders them.
--         These are NOT essentials.
--       - Essentials (sheets, metal, wheels) are general stock the Store keeps
--         regardless of any one project. When they run low the Store raises a
--         reorder request to procurement.
--
-- The Store's "Request from procurement" picker should only offer essentials —
-- a project part like an LED screen has no business being reordered by Store.
--
-- Bootstrap: existing bulk (non-serialized) items are, in practice, the general
-- essentials, so seed them as essential. Serialized items default to false
-- (project parts until someone says otherwise).

alter table public.item_catalog
  add column if not exists is_essential boolean not null default false;

update public.item_catalog set is_essential = true where serialized = false;
