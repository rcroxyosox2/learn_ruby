require 'net/http'
require 'Nokogiri'
require 'Date'
require 'Time'
require 'pp'

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

	def self.getTravelDirection(originNorthernIndex, destNorthernIndex)
		if (originNorthernIndex == destNorthernIndex) 
			raise "Origin cannot be the same as destination"
		end
		(destNorthernIndex < originNorthernIndex) ? CaltrainData.NB : CaltrainData.SB
	end

	class << self
		{
			:WEEKEND => "Weekend", 
			:WEEKDAY => "Weekday", 
			:NB=>"Northbound", 
			:SB => "Southbound",
			:AMPMTRAINS => ["426", "427", "142", "143"]
		}.each do |k,name|
			define_method(k) do
				name
			end
		end
	end

	def initialize

	end

	def self.schedule
		today = Date.today
		weekend = today.saturday? || today.sunday?
		s = CaltrainData.WEEKDAY
		s = CaltrainData.WEEKEND if weekend
		s
	end

	def self.sanitizeStop(stop)
		return stop.downcase.gsub(/[^a-z\.]/, '');
	end

	def self.stops
		stops = []
		schedule = CaltrainData.schedule
		data = CaltrainData.data
		stopNameElements = (schedule == CaltrainData.WEEKEND) ? data.css("a") : data.css(".center a")
		firstStop = stopNameElements[0];

		if (firstStop)
			startsInSf = CaltrainData.sanitizeStop(firstStop["title"]) == "sanfrancisco"
		end	

		stopNameElements.each_with_index do |item, i|
			zoneDataElements = (schedule == CaltrainData.WEEKEND) ? data.css("tbody tr")[i].css("th")[1].text : data.css("tbody tr")[i].css("th")[0].text
			nothernIndex = (startsInSf) ? i : (stopNameElements.size-1) - i
			stop = Choice.new(:text => item.text, :selection_data => zoneDataElements, :other_data => {:northern_index => nothernIndex})

			stops << stop
		end
		stops
	end

	def self.getStopListByOriginDestDir(origin="Palo Alto", destination="San Antonio", direction)
		options = {}
		data = CaltrainData.getScheduleTrainMatrix(direction)
		data.map do |trainRoutes|
			trainRoutes.each do |trainRoute|
				od = trainRoute.other_data
				(stopf, originf, destf) = [od[:stop], origin, destination].map { |item| CaltrainData.sanitizeStop(item) }
				
				if (od[:timeFromNow].to_i > 0)
					if (stopf == originf || stopf == destf) 
						train = od[:train]
						if(!options[train])
							options[train] = [od]
						else
							options[train] << od
						end
					end
				end
			end
		end

		# Remove incomplete routes
		options.each { |k, a| a.size==1 && options.delete(k) }
		# pp options
		# pp options
		options

	end

	def self.getScheduleTrainMatrix(direction)

		data = CaltrainData.weekday_data(direction)
		stopNums = data.css('thead th')

		if (CaltrainData.schedule == CaltrainData.WEEKEND)
			data = CaltrainData.weekend_data(direction)
			stopNums = data.css('thead tr')[1].css('th')
		end

		stopNums = stopNums.map do |item|
			item.text
		end

		stopTimes = data.css('tbody tr').map do |item|
			arr = []
			item.css('td, th').map do |tdth|
				arr << tdth.text
			end 
			arr
		end 

		stopMatrix = stopNums.map.with_index do |stop, i|
			arr = [stop]
			stopTimes.each do |st|
				arr << st[i]
			end
			arr
		end

		if(CaltrainData.schedule == CaltrainData.WEEKEND) 
			stopMatrix.shift
		end

		l = stopMatrix.size
		isPm = false
		stopMatrix = stopMatrix.map.with_index do |stopArr, oi|

			train = stopArr[0]

			stopArr = stopArr.map.with_index do |stopTime, i|

				isProbablyTime = (4..5).member?(stopTime.size) && stopTime.to_i && stopTime.to_i != 0
				(hour, minute) = (isProbablyTime) ? stopTime.split(":") : [0,0]

				if(CaltrainData.AMPMTRAINS.include?(train) && hour.to_i == 12)
					isPm = true
				end

				suf = (isPm) ? "pm" : "am"
				zone = stopMatrix[0][i].gsub(/[\r\n]/,"")
				stop = stopMatrix[1][i].gsub(/\r\n\s{2,}/,"")
				time = nil
				formattedTime = nil;
				timeFromNow = nil

				if (i > 0 && isProbablyTime)

					now = Time.now
					time = Time.parse("#{stopTime}#{suf}")

					# If the time goes into the next day
					if((l-3..l-1).member?(oi) && hour.to_i == 1)
						time = Time.parse("#{stopTime}am")
						time = Time.new(time.year, time.month, time.day+1, time.hour, time.min)
					end

					formattedTime = time.strftime "%-l:%M %p"
					timeFromNow = time.to_i-now.to_i
				end

				c = Choice.new(:text => "#{train} #{zone} #{stop} #{formattedTime} ", :selection_data => i, :other_data => {
					:i => i,
					:train => train,
					:zone => zone,
					:stop => stop,
					:time => time,
					:timeFromNow => timeFromNow
				})

				c
			end

		end

		if(Date.today.sunday?)
			if(direction == CaltrainData.NB)
				stopMatrix.shift
				stopMatrix.pop
			elsif(direction == CaltrainData.SB)
				2.times { stopMatrix.pop }
			end
		end

		stopMatrix
	end

	def self.weekday_data(direction=nil)
		page = Scraper.new("http://www.caltrain.com/schedules/weekdaytimetable.html").parse_page
		decide_direction_data(:direction => direction, :page => page)
	end

	def self.weekend_data(direction=nil)
		page = Scraper.new("http://www.caltrain.com/schedules/weekend-timetable.html").parse_page
		decide_direction_data(:direction => direction, :page => page)
	end

	def self.data(direction=nil)
		case CaltrainData.schedule
		when CaltrainData.WEEKEND
			weekend_data(direction)
		when CaltrainData.WEEKDAY
			weekday_data(direction)
		else
			raise "Unknow schedule given"
		end
	end

	def self.decide_direction_data(options={})
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
	attr_accessor :answer, :prev_answer, :invalid_selection_indexes, :on_before_ask

	def initialize(options={})
		@on_before_ask = options[:on_before_ask]
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
			

			!!question.on_before_ask && question.on_before_ask.call

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

stops = CaltrainData.stops.reverse;
q1 = Question.new(:qmain => "Where will you leave from?", :qchoices => stops)
q2 = Question.new(
	:on_before_ask => Proc.new { pp "Oh heeeeeyyyy" },
	:qmain => "And where you headed to?", 
	:qchoices => stops, 
	:invalid_selection_indexes => Proc.new { [q1.answer.selection_index-1] }
)

TalkBot.new.ask(q1, q2).summerize { |t|
	
	originAnswerData = t.questions[0].answer
	return unless originAnswerData

	destAnswerData = t.questions[1].answer
  	direction = CaltrainData.getTravelDirection(originAnswerData.other_data[:northern_index], destAnswerData.other_data[:northern_index])
  	# puts direction, originAnswerData.text, destAnswerData.text
  	pp CaltrainData.getStopListByOriginDestDir(originAnswerData.text, destAnswerData.text, direction)
}

CaltrainData.getStopListByOriginDestDir(CaltrainData.SB);



