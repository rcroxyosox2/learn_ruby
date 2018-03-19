class Test
	def initialize(options={})
		puts options[:thing].class
		px = options[:thing].call
		p px
	end
end

pz = Proc.new do "Hello from a proc" end
Test.new(:thing => pz)

ar = [0,1,2,3,4,5]
puts ar.class