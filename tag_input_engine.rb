require 'pp'
require 'securerandom'
require 'fileutils'
require 'taglib'
require_relative 'searcher'
require_relative 'config_reader'
require_relative 'force_quit'

class TagInputEngine

  attr_reader :offset

  YT_DOWNLOAD_CMD = 'youtube-dl --extract-audio -f bestaudio --audio-quality 0 --audio-format m4a'

  def initialize(audios, offset)
    @cur = 0
    @offset = offset
    @audios = audios
  end

  def next
    return false if @cur >= @audios.size

    a = @audios[@cur]
    @cur += 1
    @offset += 1

    puts "=== Track #{@offset} ===".green

    if a.nil?
      puts "Deleted by copyright reasons".red
      save_last_track_number
      return true
    end

    searcher = Searcher.new a

    unless process_this_track?(searcher)
      save_last_track_number
      return true
    end

    searcher.update_from_lastfm

    unless edit_before_process searcher
      save_last_track_number
      return true
    end

    url = choose_youtube_url searcher

    if url.to_s.empty?
      save_last_track_number
      return true
    end

    finished = false
    loading_arr = ['|', '/', '-', '\\']
    i = 0

    Thread.new do
      path = download_audio url, searcher
      tag_audio(path, searcher)
      finished = true
    end

    until finished
      sleep 0.2
      print "Downloading " + loading_arr[i].light_blue + "\r"
      $stdout.flush

      i += 1
      if i >= loading_arr.size
        i = 0
      end
    end

    print "\r"
    $stdout.flush
    puts "Successfully downloaded!".light_blue

    save_last_track_number

    return true
  end

  private

    def tag_audio(path, searcher)
      TagLib::MP4::File.open(File.expand_path(path)) do |mp4|
        item_list_map = mp4.tag.item_list_map
        artist_item = TagLib::MP4::Item.from_string_list([searcher.audio.artist])
        title_item = TagLib::MP4::Item.from_string_list([searcher.audio.title])
        genre_item = TagLib::MP4::Item.from_string_list([searcher.audio.genre])
        album_item = TagLib::MP4::Item.from_string_list([searcher.audio.album])
        lyrics_item = TagLib::MP4::Item.from_string_list([searcher.audio.lyrics])
        year_item = TagLib::MP4::Item.from_string_list([searcher.audio.year])

        item_list_map.insert("\xC2\xA9ART", artist_item)
        item_list_map.insert("\xC2\xA9nam", title_item)
        item_list_map.insert("\xC2\xA9gen", genre_item)
        item_list_map.insert("\xC2\xA9alb", album_item)
        item_list_map.insert("\xC2\xA9lyr", lyrics_item)
        item_list_map.insert("\xC2\xA9day", year_item)

        unless searcher.audio.cover.to_s.empty?
          begin
            image_data = Searcher::get_response_by_url(searcher.audio.cover)
          rescue Exception
            puts "Can't download cover".red
          end

          cover_art = TagLib::MP4::CoverArt.new(TagLib::MP4::CoverArt::JPEG, image_data)
          cover_item = TagLib::MP4::Item.from_cover_art_list([cover_art])

          item_list_map.insert("covr", cover_item)
        end

        mp4.save
      end
    end

    def download_audio(url, searcher)
      path = File.join(ConfigReader.download_path, searcher.audio.artist)
      path = File.join(path, "#{searcher.audio.artist} - #{searcher.audio.title}")
      `#{YT_DOWNLOAD_CMD} #{url} --output "#{path}.%(ext)s"`

      return path + ".m4a"
    end

    def print_audio_editor(searcher)
      puts searcher.audio
      puts "[(p)rocess/(r)epeat/(s)kip]".yellow + " or edit " + "[(a)rtist/(t)title/(c)over/ta(g)s/a(l)bum/(y)ear]".yellow
           + ", tags divided by ','"
    end

    def choose_youtube_url(searcher)
      videos = searcher.videos
      if videos.to_a.empty?
        puts "No tracks to download, sorry :C"
        return nil
      else
        puts "Choose what to download by putting number " + "[1/2/3/etc]".yellow + " or " + "[(n)o/(q)uit]".yellow
        videos.each_with_index { |v, i| puts "#{i + 1}: #{v}" }

        while true
          n = gets.chomp.downcase

          case n
          when 'n'
            return nil
          when 'q'
            raise ForceQuit
          when /^\d+$/
            n = n.to_i
            if n >= 1 && n <= videos.size
              return "https://www.youtube.com/watch?v=#{videos[n - 1].id}"
              break
            else
              puts "Wrong number, try again".red
            end
          end

        end
      end
    end

    def edit_before_process(searcher)
      print_audio_editor searcher

      while true
        s = gets.chomp
        case s
        when /^a .+$/
          artist = s.match(/^a (.+)$/).captures[0].strip
          searcher.update_audio_artist(artist)
        when /^t .+$/
          title = s.match(/^t (.+)$/).captures[0].strip
          searcher.update_audio_title(title)
        when /^c .+$/
          cover = s.match(/^c (.+)$/).captures[0].strip
          searcher.update_audio_cover(cover)
        when /^g .+$/
          tags = s.match(/^g (.+)$/).captures[0].strip
          searcher.update_audio_tags(tags)
        when /^l .+$/
          album = s.match(/^l (.+)$/).captures[0].strip
          searcher.update_audio_album(album)
        when /^y .+$/
          year = s.match(/^y (.+)$/).captures[0].strip
          searcher.update_audio_year(year)
        when 's'
          return false
        when 'r'
          searcher.update_from_lastfm
        when 'p'
          break
        when 'q'
          raise ForceQuit
        end

        print_audio_editor searcher
      end

      return true
    end

    def save_last_track_number
      File.open(ConfigReader.last_track_path, "w") { |f| f.write(@offset) }
    end

    def print_audio(searcher)
      puts "#{searcher.audio.artist} - #{searcher.audio.title}".blue
      puts "Process this track? " +  "[(y)es/(n)o/(l)isten/(q)uit] [(a)rtist/(t)itle]".yellow
    end

    def process_this_track?(searcher)
      print_audio searcher

      while true
        s = gets.chomp.downcase
        case s
        when /^a .+$/
          artist = s.match(/^a (.+)$/).captures[0].strip
          searcher.update_audio_artist(artist)
          print_audio searcher
        when /^t .+$/
          title = s.match(/^t (.+)$/).captures[0].strip
          searcher.update_audio_title(title)
          print_audio searcher
        when 'y'
          return true
        when 'n'
          return false
        when 'l'
          searcher.clear_videos
          videos = searcher.videos
          if videos.to_a.empty?
            puts "No tracks to listen, sorry".red
          else
            puts "Choose what to play by putting number " + "[1/2/3/etc]".yellow + " or " + "[(b)ack/(n)o/(q)uit]".yellow
            videos.each_with_index { |v, i| puts "#{i + 1}: #{v}" }

            while true
              n = gets.chomp.downcase

              case n
              when 'b'
                break
              when 'q'
                raise ForceQuit
              when 'n'
                return false
              when /^\d+$/
                n = n.to_i
                if n >= 1 && n <= videos.size
                  `open https://www.youtube.com/watch?v=#{videos[n - 1].id}`
                  break
                else
                  puts "Wrong number, try again".red
                end
              else
                puts "Wrong input. ".red + "Use [1/2/3/../(b)ack/(n)o/(q)uit]".yellow
              end
            end
            puts "Track played, process it? " + "[(y)es/(n)o/(q)uit] [(a)rtist/(t)itle]".yellow
          end
        when 'q'
          raise ForceQuit
        else
          puts "Wrong input. ".red + "Use [(y)es/(n)o/(l)isten/(q)uit]".yellow
        end
      end
    end

end

class String

  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def red
    colorize(31)
  end

  def green
    colorize(32)
  end

  def yellow
    colorize(33)
  end

  def blue
    colorize(34)
  end

  def pink
    colorize(35)
  end

  def light_blue
    colorize(36)
  end
end
