require 'io/console'
require_relative 'vk_http'
require_relative 'audio_html_parser'
require_relative 'tag_input_engine'
require_relative 'config_reader'

class Main

  def self.run
    last_track_offset_editor

    puts "Input your VK password to start parse (won't show up at the screen) or type q for quit".yellow
    password = STDIN.noecho(&:gets).to_s.chomp

    if password == 'q'
      return
    end

    vk = VkHttp.new
    until vk.login password
      if vk.captcha.to_s.empty?
        puts "Wrong VK password, try again".red
      else
        puts "Input your VK password to start parse (won't show up at the screen) or type q for quit".yellow
      end

      password = STDIN.noecho(&:gets).to_s.chomp

      if password == 'q'
        return
      end
    end

    offset = File.read(ConfigReader.last_track_path).to_i if File.file?(ConfigReader.last_track_path)
    offset = offset || 0
    html = vk.get_audio_html offset
    audios = AudioHtmlParser::parse html

    until audios.to_a.empty?
      engine = TagInputEngine.new audios, offset
      while (engine.next); end
      offset = engine.offset
      html = vk.get_audio_html offset
      audios = AudioHtmlParser::parse html
    end

    puts "Done. No more tracks".green
  rescue ForceQuit
  end

  def self.last_track_offset_editor
    last_track = 1
    last_track = File.read(ConfigReader.last_track_path).chomp.to_i + 1 if File.file?(ConfigReader.last_track_path)

    puts "Program will start from the " + last_track.to_s.yellow +
         " track. Type " + "s <number>".yellow + " to start from the " +
         "<number>".yellow + " track"
    puts "For example, to start from the first track, you should type " + "s 1".yellow
    puts "Type " + "c".yellow + " to continue, or type " + "q".yellow + " to quit"

    while true
      s = gets.chomp

      case s
      when 'c'
        return
      when 'q'
        raise ForceQuit
      when /^s (\d+)$/
        /^s (?<offset>\d+)$/ =~ s
        offset = offset.to_i

        if offset > 0
          File.open(ConfigReader.last_track_path, "w") { |f| f.write(offset - 1) }
          puts "Track successfuly changed to " + "#{offset}".yellow
          puts "Type " + "c".yellow + " to continue, or type " + "q".yellow + " to quit"
        else
          puts "<number>".yellow + " should be more than ".red + "0".yellow + ", try again".red
        end
      else
        puts "Wrong input, try again".red
      end
    end
  end

end

Main::run
