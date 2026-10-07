-- Chạy SAU khi đã upload thư mục db/seed-images/ lên R2 (giữ nguyên cấu trúc thư mục: covers/, s104/, s105/).
update stories set cover_key='covers/'||id||'.webp' where id between 101 and 105;
insert into chapter_pages(chapter_id,page_no,image_key,width,height)
select c.id,p,format('s%s/c%s/%s.webp',c.story_id,c.number,lpad(p::text,3,'0')),1080,1500
from chapters c, generate_series(1,3) p where c.story_id in (104,105)
on conflict (chapter_id,page_no) do nothing;
