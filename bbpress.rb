# Original file https://github.com/discourse/discourse/blob/master/script/import_scripts/bbpress.rb

require 'mysql2'
require 'uri'
require File.expand_path(File.dirname(__FILE__) + "/base.rb")

class ImportScripts::Bbpress < ImportScripts::Base

  BB_PRESS_HOST            ||= ENV['BBPRESS_HOST'] || "localhost"
  BB_PRESS_DB              ||= ENV['BBPRESS_DB'] || "yksivaihde"
  BATCH_SIZE               ||= 1000
  BB_PRESS_PW              ||= ENV['BBPRESS_PW'] || ""
  BB_PRESS_USER            ||= ENV['BBPRESS_USER'] || ""
  BB_PRESS_PREFIX          ||= ENV['BBPRESS_PREFIX'] || "bb_"
  BB_PRESS_ATTACHMENTS_DIR ||= ENV['BBPRESS_ATTACHMENTS_DIR'] || "/path/to/attachments"

  def initialize
    super

    @he = HTMLEntities.new

    @client = Mysql2::Client.new(
      host: BB_PRESS_HOST,
      username: BB_PRESS_USER,
      database: BB_PRESS_DB,
      password: BB_PRESS_PW,
    )
  end

  def execute
    import_users
#    import_anonymous_users
    import_categories
    import_topics_and_posts
    import_private_messages
    import_attachments
    create_permalinks
  end

  def import_users
    puts "", "importing users..."

    users = bbpress_query(<<-SQL
      SELECT u.id, u.user_nicename, u.display_name, u.user_email, u.user_registered, u.user_url, u.user_pass, p.last_seen_at, m.meta_value as avatar_url
        FROM #{BB_PRESS_PREFIX}users u
        LEFT JOIN (
          SELECT poster_id, max(post_time) as last_seen_at
          FROM bb_posts
          GROUP BY poster_id
        ) p ON p.poster_id = u.id
        LEFT JOIN (
          SELECT user_id, meta_value
          FROM bb_usermeta
          WHERE meta_key='avatar_file'
        ) m on u.id=m.user_id

    ORDER BY p.last_seen_at desc, u.user_registered desc;
    SQL
    ).to_a

    last_user_id = users[-1]["id"]
    user_ids = users.map { |u| u["id"].to_i }

    user_ids_sql = user_ids.join(",")

    users_description = {}
    bbpress_query(<<-SQL
      SELECT user_id, meta_value as description
        FROM #{BB_PRESS_PREFIX}usermeta
       WHERE user_id IN (#{user_ids_sql})
         AND meta_key = 'description'
    SQL
    ).each { |um| users_description[um["user_id"]] = um["description"] }

    users_location = {}
    bbpress_query(<<-SQL
      SELECT user_id, meta_value as location
        FROM #{BB_PRESS_PREFIX}usermeta
       WHERE user_id IN (#{user_ids_sql})
         AND meta_key = 'location'
    SQL
    ).each { |um| users_location[um["user_id"]] = um["location"] }

    users_avatar = {}
    bbpress_query(<<-SQL
      SELECT user_id, meta_value as avatar_url
      FROM bb_usermeta
      WHERE meta_key='avatar_file'
      AND user_id IN (#{user_ids_sql})
    SQL
    ).each { |um| users_avatar[um["user_id"]] = URI.encode("http://www.yksivaihde.net/site/foorumi/avatars/" + um["avatar_url"]&.split("|").dig(0)) }


    create_users(users) do |u|
      {
        id: u["id"].to_i,
        username: u["user_nicename"],
        password: SecureRandom.hex,
        email: u["user_email"].downcase,
        name: u["display_name"].presence || u['user_nicename'],
        created_at: u["user_registered"],
        website: u["user_url"],
        bio_raw: users_description[u["id"]],
        location: users_location[u["id"]],
        avatar_url: users_avatar[u["id"]],
        last_seen_at: u["last_seen_at"]
      }
    end
  end

  def import_anonymous_users
    puts "", "importing anonymous users..."

    anon_posts = Hash.new
    anon_names = Hash.new
    emails = Array.new

    # Original bbpress instance had no referential integrity and removed users were hard deleted from the database. Gather 'Anonymous' users by posts that are not associated with an author in the user table and create an unique anonymous user for each post.
    bbpress_query(<<-SQL
      SELECT post_id
        FROM #{BB_PRESS_PREFIX}posts
       WHERE user_id not in (SELECT id from bb_users)
    SQL
    ).each do |pm|
      anon_posts[pm['post_id']] = pm['post_id']
      anon_posts[pm['post_id']]['email'] = "anonymous_#{SecureRandom.hex}@no-email.invalid"
    end

    create_users(anon_names) do |k, n|
      {
        id: k,
        email: n["email"].downcase,
        name: k,
        active: false
      }
    end
  end

  def import_categories
    puts "", "importing categories..."

    categories = bbpress_query(<<-SQL
      SELECT forum_id, forum_name, forum_desc
        FROM #{BB_PRESS_PREFIX}forums
    ORDER BY forum_id
    SQL
    )

    create_categories(categories) do |c|
      category =
      {
        id: c['forum_id'],
        name: c['forum_name'],
        description: c['forum_desc']
      }
    end
  end

  def import_topics_and_posts
    puts "", "importing topics and posts..."

    last_post_id = -1
    total_posts = bbpress_query(<<-SQL
      SELECT COUNT(*) count
        FROM #{BB_PRESS_PREFIX}posts
    SQL
    ).first["count"]

    batches(BATCH_SIZE) do |offset|
      posts = bbpress_query(<<-SQL
        SELECT p.post_id as id,
               p.poster_id,
               p.post_time,
               p.post_text,
               p.post_position,
               t.topic_title,
               t.topic_id,
               t.topic_open
          FROM #{BB_PRESS_PREFIX}posts as p
          LEFT JOIN bb_topics AS t
          ON p.topic_id=t.topic_id
          WHERE p.post_id > #{last_post_id}
          AND p.post_status = 0
      ORDER BY p.post_id
         LIMIT #{BATCH_SIZE}
      SQL
      ).to_a

      break if posts.empty?

      last_post_id = posts[-1]["id"].to_i
      post_ids = posts.map { |p| p["id"].to_i }

      next if all_records_exist?(:posts, post_ids)

      post_ids_sql = post_ids.join(",")

      create_posts(posts, total: total_posts, offset: offset) do |p|
        skip = false

        user_id = user_id_from_imported_user_id(p["poster_id"]) ||
                  find_user_by_import_id(p["poster_id"]).try(:id) ||
                  -1

        post = {
          id: p["id"],
          user_id: user_id,
          raw: p["post_text"],
          created_at: p["post_time"],
        }

        if post[:raw].present?
          post[:raw].gsub!(/\<pre\>\<code(=[a-z]*)?\>(.*?)\<\/code\>\<\/pre\>/im) { "```\n#{@he.decode($2)}\n```" }
        end

        if p["post_position"] == 1
          post[:category] = category_id_from_imported_category_id(p["forum_id"])
          post[:title] = CGI.unescapeHTML(p["topic_title"])
        else
            post[:topic_id] = p["topic_id"]
        end

        skip ? nil : post
      end
    end
  end

  def create_permalinks
    puts "", "creating permalinks..."

    last_topic_id = -1

    batches(BATCH_SIZE) do |offset|
      topics = bbpress_query(<<-SQL
        SELECT id,
               guid
          FROM #{BB_PRESS_PREFIX}posts
           WHERE id > #{last_topic_id}
      ORDER BY id
         LIMIT #{BATCH_SIZE}
      SQL
      ).to_a

      break if topics.empty?
      last_topic_id = topics[-1]["id"].to_i

      topics.each do |t|
        topic = topic_lookup_from_imported_post_id(t['id'])
        Permalink.create(url: URI.parse(t['guid']).path.chomp('/'), topic_id: topic[:topic_id]) rescue nil
      end
    end
  end

  def bbpress_query(sql)
    @client.query(sql, cache_rows: false)
  end

end

ImportScripts::Bbpress.new.perform
