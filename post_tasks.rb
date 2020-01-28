

  def convert_posts
    Post.find_each do |p|
      new_raw = convert_bbpress_forum_urls(p['raw'])
      if p['raw'] != new_raw
        p['raw'] = new_raw
        p.save
      end

    end
  end

  def find_username_by_import_id(id)
    userCustomField = UserCustomField.where("name='import_id' and value='#{id}'").first
    user_id = userCustomField['user_id'] unless userCustomField.nil?
    user = User.find(user_id) rescue nil
    return user['username'] unless user.nil?
  end

