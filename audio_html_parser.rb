require 'pp'
require 'cgi'
require 'nokogiri'
require 'json'

class AudioHtmlParser

  def self.parse(data)
    result = []
    @doc = Nokogiri::HTML(data, nil, Encoding::UTF_8.to_s)

    # @doc.css('.ai_info').each_with_index do |ai_info, i|
    @doc.css('.audio_item').each_with_index do |item, i|
      ai_info = item.css('.ai_info')

      if ai_info.to_a.empty?
        result << nil
      else
        ai_info = ai_info[0]
        artist = ai_info.css('.ai_artist').text.to_s
        title = ai_info.css('.ai_title').text.to_s
        ai_play = ai_info.css('.ai_play')

        unless ai_play.to_a.empty?
          ai_play_style = ai_play[0]["style"].to_s
          /^background-image:url\((?<cover>[^\)]+)/ =~ ai_play_style
        end

        cover = cover || ""

        audio = Audio.new
        audio.title = title
        audio.artist = artist
        audio.cover = cover

        AudioHtmlParser::filter audio

        result << audio
      end
    end

    result
  end

  private

    def self.filter(audio)
      audio.title = filter_name audio.title
      audio.artist = filter_name audio.artist
    end

    def self.filter_name(n)
      return CGI.unescapeHTML(n).gsub(/[^a-z0-9а-я\s\.\,'&Σ]/i, '').chomp.strip
    end

  class Audio
    attr_accessor :title, :artist, :cover, :tags, :album, :genre, :lyrics, :year

    def to_s
      unless @lyrics.to_s.empty?
        lyrics = '+'
      end

      "@Artist: ".light_blue + colorize(@artist) + "\n" +
      "@Title: ".light_blue + colorize(@title) + "\n" +
      "@Album: ".light_blue + colorize(@album) + "\n" +
      "@Genre: ".light_blue + colorize(@genre) + "\n" +
      "@Tags: ".light_blue + colorize(@tags) + "\n" +
      "@Cover: ".light_blue + colorize(@cover) + "\n" +
      "@Lyrics: ".light_blue + colorize(lyrics) + "\n" +
      "@Year: ".light_blue + colorize(@year) + "\n"
    end

    def colorize str
      if str && str != ''
        return "#{str}".green
      else
        return "-".red
      end
    end

  end

end
