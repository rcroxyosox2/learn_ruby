class Test
	def initialize(options={})
		puts options[:thing].class
		px = options[:thing].call
		p px
	end
end

pz = Proc.new do "go fuck yourself" end
Test.new(:thing => pz)
puts pz.is_a? "Proc"

ar = [0,1,2,3,4,5]
puts ar.class