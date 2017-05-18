require 'net/http'
require 'uri'
require 'nokogiri'
require_relative 'config_reader'
require_relative 'force_quit'

# ConfigReader.vk_email

class VkHttp

  attr_reader :captcha

  def initialize
    @cookies = ''
    @headers = {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.81 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language': 'ru-RU,ru;q=0.8,en-US;q=0.6,en;q=0.4',
      'Accept-Encoding': 'gzip, deflate, sdch, br',
      'Referer': 'https://m.vk.com/',
      'Upgrade-Insecure-Requests': '1',
      'Content-Type': 'application/x-www-form-urlencoded'
    }
  end

  def login password
    http_vk = Net::HTTP.new('m.vk.com', 443)
    http_vk.use_ssl = true
    resp = http_vk.get('/', @headers)

    if resp.code == '200'
      update_cookies resp
      @cookies += '; remixmdevice=2560/1440/1.100000023841858/!!-!!!!'
      login_body = Nokogiri::HTML(resp.body, nil, Encoding::UTF_8.to_s)
      login_form = login_body.css('form')

      unless login_form.to_a.empty?
        login_path = get_path login_form[0]["action"]
        data = "email=#{ConfigReader.vk_email}&pass=#{password}#{get_captcha_part}"
        @headers['Cookie'] = @cookies

        http_login = Net::HTTP.new('login.vk.com', 443)
        http_login.use_ssl = true

        resp = http_login.post(login_path, data, @headers)
        update_cookies resp

        if process_captcha http_vk, resp["location"]
          return false
        end

        resp = http_vk.get(get_path(resp["location"]), @headers)
        cookies = resp['set-cookie']
        /^.*(?<remix_sid>remixsid=[^;]+);.*/ =~ cookies

        if remix_sid.to_s.empty? || remix_sid.include?("DELETED")
          return false
        end

        @cookies += "; " + remix_sid.to_s
        @headers['Cookie'] = @cookies

        return true
      end

      return false
    else
      return false
    end
  end

  def get_audio_html offset
    http_vk = Net::HTTP.new('m.vk.com', 443)
    http_vk.use_ssl = true
    @html = http_vk.get("/audio?offset=#{offset}", @headers).body
    @page = Nokogiri::HTML(@html, nil, Encoding::UTF_8.to_s)
    return @html
  end

  private

    def process_captcha http, location
      /.+sid=(?<captcha_sid>\d+)/ =~ location

      if !captcha_sid.to_s.empty? && @captcha_sid.to_s.empty?
        while true
          puts "Enter opened captcha or type ".red + "r".yellow + " to generate captcha again".red +
               " and ".red + "q".yellow + " for quit".red
          resp = http.get("/captcha.php?s=0&sid=#{captcha_sid}", @headers)

          File.open("captcha.jpg", "wb") do |f|
            f.write(resp.body)
          end

          File.open("captcha.html", "w") do |f|
            f.write('<html><body><img src="captcha.jpg" /></body></html>')
          end

          `open captcha.html`

          @captcha_sid = captcha_sid
          @captcha = gets.chomp

          if @captcha.to_s == 'q'
            raise ForceQuit
          end

          unless @captcha.to_s == 'r'
            break
          end
        end

        puts "Entered captcha will be used on next password attempt".green

        FileUtils.rm_f('captcha.jpg')
        FileUtils.rm_f('captcha.html')

        return true
      else
        @captcha_sid = nil
        @captcha = nil

        return false
      end
    end

    def get_captcha_part
      unless @captcha_sid.to_s.empty?
        return "&captcha_sid=#{@captcha_sid}&captcha_key=#{@captcha}"
      end

      return ""
    end

    def get_path url
      uri = URI::parse(url)
      uri.path + '?' + uri.query
    end

    def update_cookies resp
      all_cookies = resp.get_fields('set-cookie')
      cookies = Array.new
      return if all_cookies.nil?
      all_cookies.each do |cookie|
        cookies << cookie.split('; ')[0]
      end
      @cookies += cookies.join('; ')
    end

end
