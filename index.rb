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

	class << self
		{:WEEKEND => "Weekend", :WEEKDAY => "Weekday", :NB=>"Northbound", :SB => "Southbound"}.each do |k,name|
			define_method(k) do
				name
			end
		end
	end

	def initialize
		@direction = CaltrainData.NB
	end

	def schedule
		today = Date.today
		weekend = today.saturday? || today.sunday?
		s = CaltrainData.WEEKDAY
		s = CaltrainData.weekend if weekend
		s
	end

	def directions
		[Choice.new(:text => CaltrainData.NB), Choice.new(:text => CaltrainData.SB)]
	end

	def stops
		stops = []
		data.css(".center a").each_with_index do |item, i|
			stop = Choice.new(:text => item["title"], :selection_data => data.css("tbody tr")[i].css("th")[0].text)
			stops << stop
		end
		stops
	end

	def weekday_data()
		s = Scraper.new("http://www.caltrain.com/schedules/weekdaytimetable.html").parse_page
		decide_direction_data(s)
	end

	def weekend_data()
		s = Scraper.new("http://www.caltrain.com/schedules/weekend-timetable.html").parse_page
		decide_direction_data(s)
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
	def decide_direction_data(parsed_page)
		case @direction
		when CaltrainData.NB
			parsed_page.css('.NB_TT')
		when CaltrainData.SB
			parsed_page.css('.SB_TT')
		else
			raise "Unknow direction given"
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
	attr_accessor :answer, :invalid_selection_indexes
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
			puts "*************** NOW #{@invalid_selection_indexes.class == "Proc"} Proc == #{@invalid_selection_indexes.class}"
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
		previous_answer = nil
		questions.each do |question|
			result = question.ask
			if !result
				break
			else
				# puts question.answer
				previous_answer = question.answer
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
	puts t.questions[0].answer
	puts t.questions[1].answer
}


# class Requester

# 	attr_accessor :data_json, :data
# 	attr_reader :url

# 	def initialize(url)
# 		@url = url
# 		@data_json = nil
# 		@data = nil
# 	end

# 	# TODO: pass in some lambdas for success or fail
# 	def fetch
# 		ufn = @url.gsub(/[\&\/\:\=\.\?_-]/, '')
# 		fl = "./#{ufn}.json";
# 		should_query = false
# 		file_lines = []
# 		if File.file?(fl)
# 			file_lines = File.readlines(fl)
# 			if file_lines.length == 0
# 				should_query = true
# 			end
# 		end

# 		data_s = ""

# 		if should_query
# 			uri = URI(@url)
# 			res = Net::HTTP.get_response(uri) # => String

# 			# Status
# 			puts @url
# 			puts res.code       # => '200'
# 			puts res.message    # => 'OK'
# 			puts res.class.name # => 'HTTPOK'

# 			File.open(fl, 'w') do |file|
# 				file.puts(res.body)
# 				file.close
# 			end

# 			data_s = res.body
# 		else
# 			data_s = file_lines[0]
# 		end

# 		@data = data_s
# 		@data_json = JSON.parse(data_s)
# 		if block_given?
# 			@data = yield self
# 			self
# 		end
# 		self
# 	end
# end




# q1_r = Requester.new('https://transit.land/api/v1/routes?operated_by=o-9q9-caltrain&vehicle_type=rail').fetch { |r|
# 	stops = ""
# 	r.data_json['routes'].each do |route|
# 		if route["name"].downcase == "local"
# 			route["stops_served_by_route"].each_with_index do |stop, i|
# 				stops << "#{i+1}: #{stop['stop_name']}" + "\n"
# 			end
# 		end
# 	end
# 	stops
# }

# q1 = Question.new("What station are you leaving from? (Enter a station number)", q1_r).ask



#https://transit.land/feed-registry/operators/o-9q9-caltrain
# u = 'https://transit.land/api/v1/stops?served_by=o-9q9-caltrain'
# ufn = u.gsub(/[\/\:\=\.\?_-]/, '')
# fl = "./#{ufn}.json";
# mode = File.file?(fl) ? "r" : "w"
# uf = File.open(fl, mode)
# lines = uf.readlines
# should_query = (mode == "w") || (lines.length == 0)
# data_s = ""

# if should_query
# 	uri = URI(u)
# 	res = Net::HTTP.get_response(uri) # => String
# 	uf.puts res.body
# 	uf.close

# 	# Status
# 	puts u
# 	puts res.code       # => '200'
# 	puts res.message    # => 'OK'
# 	puts res.class.name # => 'HTTPOK'
# 	data_s = res.body
# else
# 	data_s = lines[0]
# end

# p File.ctime(fl);

# jp = JSON.parse(data_s)
# jp['stops'].each do |stop|
# 	p stop['name']
# end


# 0.step(100, 5) do |i|
#   printf("\rProgress: [%-20s]", "=" * (i/5))
#   sleep(0.5)
# end
# puts




# class Game
#   def self.sayhi
#   	p "hi"
#   end
# end

# class Game
# 	attr_accessor :name, :val
# 	def initialize(&block)
# 		@val = "je;;p"
#   		@name = "name"
#   		@val << "shit"
#   		self.instance_eval(&block)
# 	end
# 	def method_missing(method_name, *args)
# 		p "Oh no. You fucked up calling '#{method_name} with #{args}'"
# 		super
# 	end
# end

# g = Game.new { |game|
# 	def self.t
# 		p "ttttttt"
# 	end
# }
# begin
# 	g.fuck
# rescue Exception => e
# 	p e
# end

# b = g.method(:t)
# b.call




# Game.class_eval do
#   def self.find_by_owner(name)
#   	p name
#   end
# end

# Game.sayhi

# Game.find_by_owner "He"

# e = proc { |t| p t }
# ["one", "two", "three"].each &e

# puts self

# class Library
#   attr_accessor :games

#   def initialize(games)
#     @games = games
#   end

#   def each(&block)
#     games.each do |game|
#       block.call(game)
#     end
#   end
# end


# l = Library.new(["one", "tow", "three"])
# l.each {|game| p game}
# def weird(x, y)
# 	lambda { |a,b| p "#{x}: #{y} #{a}: #{b}" }
# end

# weird("xxx","yyy").call("ds","bs")


# class Thing
# 	attr_accessor :thing
# 	def initialize(thing)
# 		@thing = thing
# 	end
# 	def say
# 		p @thing
# 	end
# end

# class CoolThing
# 	attr_accessor :x, :y
# 	def initialize(options={})
# 		if block_given?
# 			yield self
# 		else
# 			p options
# 			@x=options[:x], @y=options[:y]
# 		end
# 	end
# end

# ct = CoolThing.new do |o|
# 	o.x = "xxx"
# 	o.y = "yyyy"
# end

# ct2 = CoolThing.new({:x => "The X", :y => "The Y"})
# p ct, ct2


# things = [Thing.new("First"), Thing.new("Second"), Thing.new("Third")]
# doit = proc { |x| p x.thing}
# things.each(&:say)
# p "______________"
# things.each(&doit)
# p "______________"
# things.each do |thing|
# 	thing.say
# end









