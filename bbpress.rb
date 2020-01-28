# frozen_string_literal: true
# Original file https://github.com/discourse/discourse/blob/master/script/import_scripts/bbpress.rb

require 'htmlentities'
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
    create_anonymous_user
    import_users
    import_categories
    import_topics_and_posts
  end

  def import_users
    puts "", "importing users..."

    users = bbpress_query(<<-SQL
      SELECT u.id, u.user_nicename, u.user_login, u.user_email, u.user_registered, u.user_url, u.user_pass, p.last_seen_at, m.meta_value as avatar_url
        FROM wp_users u
        LEFT JOIN (
          SELECT poster_id, max(post_time) as last_seen_at
          FROM bb_posts
          GROUP BY poster_id
        ) p ON p.poster_id = u.id
        LEFT JOIN (
          SELECT user_id, meta_value
          FROM wp_usermeta
          WHERE meta_key='avatar_file'
        ) m on u.id=m.user_id

    ORDER BY p.last_seen_at desc, u.user_registered desc
    SQL
    ).to_a

    last_user_id = users[-1]["id"]
    user_ids = users.map { |u| u["id"].to_i }

    user_ids_sql = user_ids.join(",")

    users_description = {}
    bbpress_query(<<-SQL
      SELECT user_id, meta_value as description
        FROM wp_usermeta
       WHERE user_id IN (#{user_ids_sql})
         AND meta_key = 'description'
    SQL
    ).each { |um| users_description[um["user_id"]] = um["description"] }

    users_location = {}
    bbpress_query(<<-SQL
      SELECT user_id, meta_value as location
        FROM wp_usermeta
       WHERE user_id IN (#{user_ids_sql})
         AND meta_key = 'location'
    SQL
    ).each { |um| users_location[um["user_id"]] = um["location"] }

    users_avatar = {}
    bbpress_query(<<-SQL
      SELECT user_id, meta_value as avatar_url
      FROM wp_usermeta
      WHERE meta_key='avatar_file'
      AND user_id IN (#{user_ids_sql})
    SQL
    ).each { |um| users_avatar[um["user_id"]] = URI.encode("http://www.yksivaihde.net/site/foorumi/avatars/" + um["avatar_url"]&.split("|").dig(0)) }


    create_users(users) do |u|
      {
        id: u["id"].to_i,
        username: u["user_login"],
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

  # Create anonymous user to be substituted as post author if original author is missing from user table
  def create_anonymous_user
    puts "", "creating anonymous user..."

    users = [
        id: "-666",
        email: "anonymous_#{SecureRandom.hex}@no-email.invalid".to_s,
        name: "Anonymous"
    ]

    create_users(users) do |u|
    {
        id: u[:id].to_i,
        email: u[:email].downcase,
        name: u[:name],
        active: false
    }
    end
  end

  def import_categories
    puts "", "importing categories..."

    categories = bbpress_query(<<-SQL
      SELECT forum_id, forum_name, forum_desc
        FROM bb_forums
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

    puts "Creating permalinks for categories"
    categories.each do |c|
        Permalink.create(
            url: "old_cat/"+c["forum_id"].to_s,
            category_id: category_id_from_imported_category_id(c["forum_id"])
        ) rescue nil
    end

  end

  def import_topics_and_posts
    puts "", "importing topics and posts..."

    last_post_id = -1
    total_posts = bbpress_query(<<-SQL
      SELECT COUNT(*) count
        FROM bb_posts
    SQL
    ).first["count"]

    batches(BATCH_SIZE) do |offset|
      posts = bbpress_query(<<-SQL
        SELECT p.post_id as id,
               p.poster_id,
               p.post_time,
               p.post_text,
               p.post_position,
               p.forum_id,
               t.topic_title,
               t.topic_id,
               t.topic_open,
               t.topic_status
          FROM bb_posts as p
          INNER JOIN bb_topics AS t
          ON p.topic_id=t.topic_id
          WHERE p.post_id > #{last_post_id}
          AND p.post_status = 0
          AND t.topic_status = 0
          AND t.topic_title IS NOT NULL
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
                  find_user_by_import_id(-666).try(:id) ||
                  -1

        post = {
          id: p["id"],
          user_id: user_id,
          raw: preprocess_post_raw(p["post_text"]),
          created_at: p["post_time"]
        }

        if p["post_position"] == 1
          post[:category] = category_id_from_imported_category_id(p["forum_id"])
          post[:title] = CGI.unescapeHTML(p["topic_title"])
          post[:closed] = p["topic_open"].to_i.zero?
        else
          parent_post_id=bbpress_query(<<-SQL
            SELECT post_id
            FROM bb_posts
            WHERE topic_id=#{p["topic_id"]}
            AND post_position=1
          SQL
           ).first["post_id"]
          if parent_topic = topic_lookup_from_imported_post_id(parent_post_id)
              post[:topic_id] = parent_topic[:topic_id]
              post[:reply_to_post_number] = parent_topic[:post_number] if parent_topic[:post_number] > 1
          else
            puts "Unable to associate post with import id #{p["id"]} to parent topic #{p["topic_id"]} : #{p["post_text"][0..40]}"
            skip = true
          end
        end
        skip ? nil : post
      end

      posts.each do |p|
        post_id = post_id_from_imported_post_id(p["post_id"])
        topic_id = topic_lookup_from_imported_post_id(p["post_id"])[:topic_id]

        unless post_id > 0
            puts ""
            puts "Unable to create permalink with bbpress id #{p["post_id"]}. Post not found in discourse"
            break
        end

        topic_url = "old/#{p["topic_id"]}"
        post_url = topic_url + "/#{p["post_id"]}"

        Permalink.create(post_id: post_id, url: post_url) rescue nil
        Permalink.create(topic_id: topic_id, url: topic_url) rescue nil
      end
    end
  end

  def bbpress_query(sql)
    @client.query(sql, cache_rows: false)
  end

  def convert_bbpress_forum_urls(raw)

    # trim markdown url format '[]()' to avoid URI.extract parsing trailing )'s or ]'s
    URI.extract(raw.gsub(/\((.*?)\)/i, ' \1 ').gsub(/\[(.*?)\]/i, ' \1 '), 'http') do |u|
      uri = URI(u)

      next if uri.host != "www.yksivaihde.net"
      next if uri.query.nil?

      # sanity check to trim any residue markdown that gets passed through by URI.extract
      if u.to_s.match(/.+#post-[0-9]+/) != nil
        uri = URI(uri.to_s.match(/(.+#post-[0-9]+)/i) {$1}) rescue nil

      elsif u.to_s.match(/.+id=[0-9]+/) != nil
        uri = URI(uri.to_s.match(/(.+#id=[0-9]+)/i) {$1}) rescue nil
      else
          p uri
          next
      end

      uri_query_id = URI.decode_www_form(uri.query).assoc('id')&.last.to_i rescue nil

      next if uri_query_id.nil?

      new_uri = URI("https://" + uri.host)
      converted = false

      if uri.path == "/site/foorumi/topic.php"
        new_uri.path = "/old/#{uri_query_id}"

        post_id = uri.fragment.match(/post\-([0-9]+)/i) {$1} unless uri.fragment.nil?
        if post_id != nil && post_id == 0
            puts "#{ uri.to_s}"
        end

        new_uri.path += "/#{post_id.to_i}" unless post_id.nil?

        converted = true

      elsif uri.path == "/site/foorumi/forum.php"
        new_uri.path = "/old_cat/#{uri_query_id}"
        converted = true

      elsif uri.path == "/site/foorumi/profile.php"
        user = find_username_by_import_id(uri_query_id)
        unless user.nil?
          new_uri.path = "/u/#{user}"
          converted = true
        end

      elsif uri.path == "/site/foorumi/search.php"
          new_uri.path = "/search?q=#{uri_query_id}"
          converted=true
      end

      # todo /site/foorumi/avatar/#{fetch_avatar_by_import_username(...)}

      raw = raw.gsub(uri.to_s, new_uri.to_s) if converted
    rescue => error
        p error.message
    end

    raw
  end

  def preprocess_post_raw(raw)
    return "" if raw.blank?

    # decode HTML entities
    raw = @he.decode(raw)

    # Convert bbpress urls to discourse permalink format
    raw = convert_bbpress_forum_urls(raw)

    # fix whitespaces
    raw.gsub!(/(\\r)?\\n/, "\n")
    raw.gsub!("\\t", "\t")

    # [HIGHLIGHT="..."]
    raw.gsub!(/\[highlight="?(\w+)"?\]/i) { "\n```#{$1.downcase}\n" }

    # [CODE]...[/CODE]
    # [HIGHLIGHT]...[/HIGHLIGHT]
    raw.gsub!(/\[\/?code\]/i, "\n```\n")
    raw.gsub!(/\[\/?highlight\]/i, "\n```\n")

    # [SAMP]...[/SAMP]
    raw.gsub!(/\[\/?samp\]/i, "`")

    # replace all chevrons with HTML entities
    # NOTE: must be done
    #  - AFTER all the "code" processing
    #  - BEFORE the "quote" processing
   # raw.gsub!(/`([^`]+)`/im) { "`" + $1.gsub("<", "\u2603") + "`" }
   # raw.gsub!("<", "&lt;")
   # raw.gsub!("\u2603", "<")

   # raw.gsub!(/`([^`]+)`/im) { "`" + $1.gsub(">", "\u2603") + "`" }
   # raw.gsub!(">", "&gt;")
   # raw.gsub!("\u2603", ">")

    # [URL=...]...[/URL]
    raw.gsub!(/\[url="?([^"]+?)"?\](.*?)\[\/url\]/im) { "[#{$2.strip}](#{$1})" }
    raw.gsub!(/\[url="?(.+?)"?\](.+)\[\/url\]/im) { "[#{$2.strip}](#{$1})" }

    # [URL]...[/URL]
    # [img]...[/img]
    # <p>...</p>
    raw.gsub!(/\[\/?url\]/i, "")
    raw.gsub!(/\[\/?img\]/i, "")
    raw.gsub!(/\<\/?p\>/i, "")

    # [FONT=blah] and [COLOR=blah]
    raw.gsub! /\[FONT=.*?\](.*?)\[\/FONT\]/im, '\1'
    raw.gsub! /\[COLOR=.*?\](.*?)\[\/COLOR\]/im, '\1'
    raw.gsub! /\[COLOR=#.*?\](.*?)\[\/COLOR\]/im, '\1'

    raw.gsub! /\[SIZE=.*?\](.*?)\[\/SIZE\]/im, '\1'
    raw.gsub! /\[SUP\](.*?)\[\/SUP\]/im, '\1'
    raw.gsub! /\[h=.*?\](.*?)\[\/h\]/im, '\1'

    # [CENTER]...[/CENTER]
    raw.gsub! /\[CENTER\](.*?)\[\/CENTER\]/im, '\1'

    # [INDENT]...[/INDENT]
    raw.gsub! /\[INDENT\](.*?)\[\/INDENT\]/im, '\1'

    # Tables to MD
    raw.gsub!(/\[TABLE.*?\](.*?)\[\/TABLE\]/im) { |t|
      rows = $1.gsub!(/\s*\[TR\](.*?)\[\/TR\]\s*/im) { |r|
        cols = $1.gsub! /\s*\[TD.*?\](.*?)\[\/TD\]\s*/im, '|\1'
        "#{cols}|\n"
      }
      header, rest = rows.split "\n", 2
      c = header.count "|"
      sep = "|---" * (c - 1)
      "#{header}\n#{sep}|\n#{rest}\n"
    }

    # [YOUTUBE]<id>[/YOUTUBE]
    raw.gsub!(/\[youtube\](.+?)\[\/youtube\]/i) { "\n//youtu.be/#{$1}\n" }

    # [VIDEO=youtube;<id>]...[/VIDEO]
    raw.gsub!(/\[video=youtube;([^\]]+)\].*?\[\/video\]/i) { "\n//youtu.be/#{$1}\n" }

    # Fix uppercase B U and I tags
    raw.gsub!(/(\[\/?[BUI]\])/i) { $1.downcase }

    # More Additions ....

    # [spoiler=Some hidden stuff]SPOILER HERE!![/spoiler]
    raw.gsub!(/\[spoiler="?(.+?)"?\](.+?)\[\/spoiler\]/im) { "\n#{$1}\n[spoiler]#{$2}[/spoiler]\n" }

    # [IMG][IMG]http://i63.tinypic.com/akga3r.jpg[/IMG][/IMG]
    raw.gsub!(/\[IMG\]\[IMG\](.+?)\[\/IMG\]\[\/IMG\]/i) { "[IMG]#{$1}[/IMG]" }

    # convert list tags to ul and list=1 tags to ol
    # (basically, we're only missing list=a here...)
    # (https://meta.discourse.org/t/phpbb-3-importer-old/17397)
    raw.gsub!(/\[list\](.*?)\[\/list\]/im, '[ul]\1[/ul]')
    raw.gsub!(/\[list=1\](.*?)\[\/list\]/im, '[ol]\1[/ol]')
    raw.gsub!(/\[list\](.*?)\[\/list:u\]/im, '[ul]\1[/ul]')
    raw.gsub!(/\[list=1\](.*?)\[\/list:o\]/im, '[ol]\1[/ol]')
    # convert *-tags to li-tags so bbcode-to-md can do its magic on phpBB's lists:
    raw.gsub!(/\[\*\]\n/, '')
    raw.gsub!(/\[\*\](.*?)\[\/\*:m\]/, '[li]\1[/li]')
    raw.gsub!(/\[\*\](.*?)\n/, '[li]\1[/li]')
    raw.gsub!(/\[\*=1\]/, '')

    raw
  end
end
ImportScripts::Bbpress.new.perform
