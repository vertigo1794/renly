-- supabase/migrations/0033_chat_attachments.sql
-- Adds image attachment support to chat messages: a nullable
-- attachment_url column on `message`, plus a private `chat-attachments`
-- Storage bucket scoped to the two parties of the underlying accepted
-- cobroke_request. Mirrors 0003_listing.sql's bucket+RLS pattern and
-- 0008_messaging.sql's accepted-request party check.

-- message.body was NOT NULL; an image-only message has no text, so it
-- must become nullable. The old non-empty-text check is replaced with a
-- "has text OR has attachment" check so a message can never be neither.
alter table message alter column body drop not null;
alter table message drop constraint if exists message_body_check;
alter table message add column if not exists attachment_url text;
alter table message add constraint message_has_content_check
  check (
    (body is not null and char_length(trim(body)) > 0)
    or attachment_url is not null
  );

-- Column-level grant must be extended to include the new column, same
-- gotcha as every other column-restricted insert grant in this codebase
-- (see 0008_messaging.sql) -- RLS passing is not enough, the column also
-- needs an explicit grant or the insert is rejected.
grant insert (request_id, sender_id, body, attachment_url) on message to authenticated;

-- Storage: path convention {request_id}/{timestamp}.jpg
insert into storage.buckets (id, name, public) values ('chat-attachments', 'chat-attachments', false)
  on conflict (id) do nothing;

-- Reuse the same accepted-request party check as message_select/message_insert:
-- the storage path's first folder segment is the request_id, so a party to
-- that request (its initiator, or whichever side of the match's
-- listing/requirement they own) may read/write files under it.
create policy chat_attachments_select on storage.objects for select
  to authenticated using (
    bucket_id = 'chat-attachments'
    and exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      where cr.request_id::text = (storage.foldername(name))[1]
        and cr.status = 'accepted'
        and (
          cr.initiator_id = auth.uid()
          or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = auth.uid())
          or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = auth.uid())
        )
    )
  );

create policy chat_attachments_insert on storage.objects for insert
  to authenticated with check (
    bucket_id = 'chat-attachments'
    and exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      where cr.request_id::text = (storage.foldername(name))[1]
        and cr.status = 'accepted'
        and (
          cr.initiator_id = auth.uid()
          or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = auth.uid())
          or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = auth.uid())
        )
    )
  );

update storage.buckets
set file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png']
where id = 'chat-attachments';
