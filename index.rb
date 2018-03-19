require 'net/http'
require 'Nokogiri'
require 'Date'

class String
	# colorization
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


class Scraper 
	attr_accessor :url, :parse_page

	def initialize(url)
		@url = url

		ufn = @url.gsub(/[\&\/\:\=\.\?_-]/, '')
		fl = "./#{ufn}.html";
		should_query = false
		if File.file?(fl)
			file_contents = File.read(fl)
			if file_contents.strip.length == 0
				should_query = true
			end
		else
			should_query = true
		end

		data_s = ""

		if should_query
			uri = URI(@url)
			res = Net::HTTP.get_response(uri) # => String

			# Status
			puts @url
			puts res.code       # => '200'
			puts res.message    # => 'OK'
			puts res.class.name # => 'HTTPOK'

			File.open(fl, 'w') do |file|
				file.puts(res.body)
				file.close
			end

			data_s = res.body
		else
			data_s = file_contents
		end

		@parse_page ||= Nokogiri::HTML(data_s)

	end
end

class CaltrainData

	def self.singleton
		CaltrainData.new
	end

	def self.getTravelDirection(originNorthernIndex, destNorthernIndex)
		(destNorthernIndex < originNorthernIndex) ? CaltrainData.NB : CaltrainData.SB
	end


	class << self
		{:WEEKEND => "Weekend", :WEEKDAY => "Weekday", :NB=>"Northbound", :SB => "Southbound"}.each do |k,name|
			define_method(k) do
				name
			end
		end
	end

	def initialize

	end

	def schedule
		today = Date.today
		weekend = today.saturday? || today.sunday?
		s = CaltrainData.WEEKDAY
		s = CaltrainData.WEEKEND if weekend
		s
	end

	def directions
		[Choice.new(:text => CaltrainData.NB), Choice.new(:text => CaltrainData.SB)]
	end

	def stops
		stops = []
		stopNameElements = (schedule == CaltrainData.WEEKEND) ? data.css("a") : data.css(".center a")
		startsInSf = stopNameElements[0]["title"].downcase.gsub(/\s+/, "") == "sanfrancisco"

		stopNameElements.each_with_index do |item, i|
			zoneDataElements = (schedule == CaltrainData.WEEKEND) ? data.css("tbody tr")[i].css("th")[1].text : data.css("tbody tr")[i].css("th")[0].text
			nothernIndex = (startsInSf) ? i : (stopNameElements.size-1) - i
			stop = Choice.new(:text => item["title"], :selection_data => zoneDataElements, :other_data => {:northern_index => nothernIndex})

			stops << stop
		end
		stops
	end

	def weekday_data(direction=nil)
		page = Scraper.new("http://www.caltrain.com/schedules/weekdaytimetable.html").parse_page
		decide_direction_data(:direction => direction, :page => page)
	end

	def weekend_data(direction=nil)
		page = Scraper.new("http://www.caltrain.com/schedules/weekend-timetable.html").parse_page
		decide_direction_data(:direction => direction, :page => page)
	end


	private
	def data
		case schedule
		when CaltrainData.WEEKEND
			weekend_data
		when CaltrainData.WEEKDAY
			weekday_data
		else
			raise "Unknow schedule given"
		end
	end

	protected
	def decide_direction_data(options={})
		case options[:direction]
		when CaltrainData.NB, nil
      options[:page].css('.NB_TT')
		when CaltrainData.SB
      options[:page].css('.SB_TT')
		else
			raise "Unknow direction given: #{options[:direction]}"
		end
	end
end

class Choice
	attr_accessor :text, :selection_data, :selection_index, :other_data
	def initialize(options={})
		@text = options[:text]
		@selection_data = options[:selection_data]
		@other_data = options[:other_data]
	end
	def to_s
		"text: #{@text}, selection_data: #{@selection_data}, selection_index: #{@selection_index}, other_data: #{@other_data}"
	end
end

class Question
	BREAK_OUT_CHAR = "x"
	attr_accessor :answer, :prev_answer, :invalid_selection_indexes

	def initialize(options={})
		@qmain = options[:qmain]
		@qchoices = options[:qchoices]		
		@invalid_selection_indexes = options[:invalid_selection_indexes]
  end

	def qchoices
		@qchoices.each_with_index.map do |item, i|
			item.selection_index = i
			"#{i+1}: #{item.text} #{item.selection_data}"
		end
  end

	def ask
		ret = false
		loop do
			puts "\n"
			puts @qmain
			sleep(0.5)
			puts qchoices
			puts "\n" 
			selection = gets.chomp
			selection_int = selection.to_i

			isi = []
			# puts "*************** NOW #{@invalid_selection_indexes.class == "Proc"} Proc == #{@invalid_selection_indexes.class}"
			if @invalid_selection_indexes.class == "Array"
				isi = @invalid_selection_indexes
			elsif @invalid_selection_indexes.class == "Proc"

				isi = @invalid_selection_indexes.call
			end

			if selection.downcase == BREAK_OUT_CHAR
				ret = false
				break
			elsif selection_int == 0 || qchoices[selection_int-1] == nil || isi.include?(selection_int)
				puts "\n"
				puts "Not a valid option, try again"
			else
				@answer = @qchoices[selection_int-1]
				ret = true
				break
			end
		end
		ret
	end
end

class TalkBot
	attr_accessor :questions
	def initialize()
	end
	def ask(*questions)
		@questions = questions
		questions.each_with_index do |question, i|
			result = question.ask
			if !result
				break
			else
				pq = questions[i-1]
				question.prev_answer = (pq) ? pq.answer : nil
			end
		end
		self
	end
	def summerize
		yield self
	end
end

stops = CaltrainData.singleton.stops.reverse;
q1 = Question.new(:qmain => "Where will you leave from?", :qchoices => stops)
q2 = Question.new(:qmain => "And where you headed to?", :qchoices => stops, :invalid_selection_indexes => Proc.new { [q1.answer.selection_index-1] })

TalkBot.new.ask(q1, q2).summerize { |t|
	originAnswerData = t.questions[0].answer
	destAnswerData = t.questions[1].answer
  puts CaltrainData.getTravelDirection(originAnswerData.other_data[:northern_index], destAnswerData.other_data[:northern_index])
}
