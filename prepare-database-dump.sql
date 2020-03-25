use yksivaihde;

-- When first post of topic is moderated/modified, it can create a new post id with post_position=1
-- Find topics with multiple "first posts", set the content of the first id to that of the max id,
-- and delete the rest of the rows

select topic_id from bb_posts where post_position=1 group by topic_id having count(post_id) > 1;

-- should yield the following result set with an unmodified dump
-- +----------+
-- | topic_id |
-- +----------+
-- |       56 |
-- |      115 |
-- |      874 |
-- |     3153 |
-- |     6690 |
-- |     9995 |
-- |    13955 |
-- |    29091 |
-- +----------+


set @topic_id=56;
set @min_post_id = ( select post_id from bb_posts where post_position=1 and topic_id=@topic_id order by post_id asc limit 1);
set @text = (select post_text from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
set @post_status = (select post_status from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
update bb_posts set post_text=@text where post_id=@min_post_id;
update bb_posts set post_status=@post_status where post_id=@min_post_id;
delete from bb_posts where topic_id=@topic_id and post_position=1 and post_id != @min_post_id;

set @topic_id=115;
set @min_post_id = ( select post_id from bb_posts where post_position=1 and topic_id=@topic_id order by post_id asc limit 1);
set @text = (select post_text from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
set @post_status = (select post_status from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
update bb_posts set post_text=@text where post_id=@min_post_id;
update bb_posts set post_status=@post_status where post_id=@min_post_id;
delete from bb_posts where topic_id=@topic_id and post_position=1 and post_id != @min_post_id;

set @topic_id=874;
set @min_post_id = ( select post_id from bb_posts where post_position=1 and topic_id=@topic_id order by post_id asc limit 1);
set @text = (select post_text from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
set @post_status = (select post_status from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
update bb_posts set post_text=@text where post_id=@min_post_id;
update bb_posts set post_status=@post_status where post_id=@min_post_id;
delete from bb_posts where topic_id=@topic_id and post_position=1 and post_id != @min_post_id;

set @topic_id=3153;
set @min_post_id = ( select post_id from bb_posts where post_position=1 and topic_id=@topic_id order by post_id asc limit 1);
set @text = (select post_text from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
set @post_status = (select post_status from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
update bb_posts set post_text=@text where post_id=@min_post_id;
update bb_posts set post_status=@post_status where post_id=@min_post_id;
delete from bb_posts where topic_id=@topic_id and post_position=1 and post_id != @min_post_id;

set @topic_id=6690;
set @min_post_id = ( select post_id from bb_posts where post_position=1 and topic_id=@topic_id order by post_id asc limit 1);
set @text = (select post_text from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
set @post_status = (select post_status from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
update bb_posts set post_text=@text where post_id=@min_post_id;
update bb_posts set post_status=@post_status where post_id=@min_post_id;
delete from bb_posts where topic_id=@topic_id and post_position=1 and post_id != @min_post_id;

set @topic_id=9995;
set @min_post_id = ( select post_id from bb_posts where post_position=1 and topic_id=@topic_id order by post_id asc limit 1);
set @text = (select post_text from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
set @post_status = (select post_status from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
update bb_posts set post_text=@text where post_id=@min_post_id;
update bb_posts set post_status=@post_status where post_id=@min_post_id;
delete from bb_posts where topic_id=@topic_id and post_position=1 and post_id != @min_post_id;

set @topic_id=13955;
set @min_post_id = ( select post_id from bb_posts where post_position=1 and topic_id=@topic_id order by post_id asc limit 1);
set @text = (select post_text from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
set @post_status = (select post_status from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
update bb_posts set post_text=@text where post_id=@min_post_id;
update bb_posts set post_status=@post_status where post_id=@min_post_id;
delete from bb_posts where topic_id=@topic_id and post_position=1 and post_id != @min_post_id;

set @topic_id=29091;
set @min_post_id = ( select post_id from bb_posts where post_position=1 and topic_id=@topic_id order by post_id asc limit 1);
set @text = (select post_text from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
set @post_status = (select post_status from bb_posts where post_position=1 and topic_id=@topic_id order by post_id desc limit 1);
update bb_posts set post_text=@text where post_id=@min_post_id;
update bb_posts set post_status=@post_status where post_id=@min_post_id;
delete from bb_posts where topic_id=@topic_id and post_position=1 and post_id != @min_post_id;

-- should yield an empty result set now
select topic_id from bb_posts where post_position=1 group by topic_id having count(post_id) > 1;


