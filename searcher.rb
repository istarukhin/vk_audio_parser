require 'net/http'
require 'open-uri'
require_relative 'config_reader'

class Searcher

  attr_reader :audio

  YT_URL = 'https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&maxResults='
  YT_V_URL = 'https://www.googleapis.com/youtube/v3/videos?part=contentDetails,statistics'
  LFM_URL = 'http://ws.audioscrobbler.com/2.0/?method=track.getInfo&format=json&autocorrect=1'
  LFM_A_URL = 'http://ws.audioscrobbler.com/2.0/?method=artist.getInfo&format=json'

  def initialize(audio)
    @audio = audio
  end

  def clear_videos
    @videos = nil
  end

  def videos
    unless @videos
      @videos = Searcher::get_videos_by_query("#{@audio.artist} - #{@audio.title}")
    end

    @videos
  end

  def get_lyrics url
    doc = Nokogiri::HTML(open(url), nil, Encoding::UTF_8.to_s)
    lyrics_tag = doc.css('.lyrics-section p a')

    return "" if lyrics_tag.to_a.empty?
    lyrics_href = lyrics_tag[0]["href"]
    return  "" if lyrics_href.to_s.empty?

    lyrics = ""
    doc = Nokogiri::HTML(open(lyrics_href), nil, Encoding::UTF_8.to_s)
    doc.css('#lyrics-body-text .verse').each do |v|
      lyrics += v.text.to_s + "\n\n"
    end

    lyrics = lyrics[0..-3] unless lyrics.empty?

    return lyrics
  end

  def update_from_lastfm
    @audio.tags = []
    json = JSON.parse(Searcher::get_response_by_url(URI.escape("#{LFM_URL}&api_key=#{ConfigReader.lastfm_key}&artist=#{@audio.artist}&track=#{@audio.title}")))
    track = json["track"]
    unless track.to_s.empty?
      artist = track["artist"]
      album = track["album"]
      toptags = track["toptags"]
      title = track["name"]
      url = track["url"]
      lyrics = get_lyrics(url)
      wiki = track["wiki"]

      unless title.to_s.empty?
        @audio.title = title
      end

      unless artist.to_s.empty?
        @audio.artist = artist["name"]
      end

      unless lyrics.to_s.empty?
        @audio.lyrics = lyrics
      end

      unless wiki.to_s.empty?
        published = wiki["published"]

        unless published.to_s.empty?
          /^\d+ [a-z]+ (?<year>\d+), \d+:\d+$/i =~ published
          @audio.year = year
        end
      end

      unless album.to_s.empty?
        image = album["image"]
        @audio.album = album["title"]

        unless image.to_s.empty?
          @audio.cover = image[-1]["#text"]
        end
      end

      if !toptags.to_s.empty? && !toptags["tag"].to_a.empty?
        @audio.tags = toptags["tag"].map { |tag| tag["name"] }

        unless @audio.tags.to_a.empty?
          @audio.genre = @audio.tags[0].split.map(&:capitalize).join(' ')
        end
      end
    end

    json = JSON.parse(Searcher::get_response_by_url(URI.escape("#{LFM_A_URL}&api_key=#{ConfigReader.lastfm_key}&artist=#{@audio.artist}")))
    artist = json["artist"]

    unless artist.to_s.empty?
      image = artist["image"]
      tags = artist["tags"]

      if !image.to_s.empty? && @audio.cover.to_s.empty?
        @audio.cover = image[-1]["#text"]
      end

      if !tags.to_s.empty? && !tags["tag"].to_a.empty?
        if @audio.tags.to_a.empty?
          @audio.tags = []
        end

        @audio.tags += tags["tag"].map { |tag| tag["name"] }.to_a

        unless @audio.tags.to_a.empty?
          @audio.genre = @audio.tags[0].split.map(&:capitalize).join(' ')
        end

      end

    end
  end

  def update_audio_artist(artist)
    @audio.artist = artist.split.map(&:capitalize).join(' ')
  end

  def update_audio_title(title)
    @audio.title = title.split.map(&:capitalize).join(' ')
  end

  def update_audio_cover(cover)
    @audio.cover = cover
  end

  def update_audio_tags(tags)
    tags_arr = tags.split(',')
    @audio.tags = tags_arr.map(&:strip)

    unless tags_arr.to_a.empty?
      @audio.genre = tags_arr[0].split.map(&:capitalize).join(' ')
    end
  end

  def update_audio_album(album)
    @audio.album = album.split.map(&:capitalize).join(' ')
  end

  def update_audio_year(year)
    @audio.year = year.split.map(&:capitalize).join(' ')
  end

  def self.get_response_by_url(url_s)
    url = URI.parse(url_s)
    req = Net::HTTP::Get.new(url)
    res = Net::HTTP.start(url.host, url.port, :use_ssl => url.scheme == 'https') { |http|
      http.request(req)
    }

    return res.body
  end

  private

    def self.get_videos_by_query(query)
      json = JSON.parse(get_response_by_url(URI.escape("#{YT_URL}#{ConfigReader.youtube_max_results}&key=#{ConfigReader.youtube_key}&q=#{query}")))
      result = []

      if json && json["items"] && !json["items"].to_a.empty?
        ids = json["items"].map { |item| item["id"]["videoId"] }.join ','
        names = Hash.new
        years = Hash.new

        json["items"].each { |item| names[item["id"]["videoId"]] = item["snippet"]["title"] }
        json["items"].each { |item| years[item["id"]["videoId"]] = item["snippet"]["publishedAt"][0..3] }

        json = JSON.parse(get_response_by_url(URI.escape("#{YT_V_URL}&key=#{ConfigReader.youtube_key}&id=#{ids}")))
        json["items"].each do |item|
          video = Video.new
          video.id = item["id"]
          video.title = names[video.id]
          video.views = item["statistics"]["viewCount"].to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
          video.year = years[video.id]
          video.duration = item["contentDetails"]["duration"]
            .gsub("PT", "")
            .gsub("H", "H ")
            .gsub("M", "M ")
            .gsub("S", "S ")
            .strip
            .downcase
          result << video
        end
      end

      result
    end

    class Video
      attr_accessor :id, :title, :views, :duration, :year

      def to_s
        @title.blue + " (" + @views.pink + " views, " + @year.light_blue + " year) [" + @duration.red + "]"
      end
    end

end
