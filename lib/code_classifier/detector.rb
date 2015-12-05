
module CodeClassifier
  # Your code goes here...
  class Detector

		def initialize(classifier)
			@classifier = classifier
		end

		def predict(str)
			@classifier.classify(str)
		end

		def train(training_set)
			languages = Dir.glob("#{training_set}/*").map{|pa| pa.split('/').last}
			@classifier = ClassifierReborn::Bayes.new languages
			languages.each do |language|
				files = Dir.glob("#{training_set}/#{language}/*")
				content = ""
				files.each do |file|
					content << File.open(file).read
				end
				@classifier.train(language, content)
			end
		end

		def self.load_from_file(file)
			data = File.read(file)
			classifier = Marshal.load data
			self.new(classifier)
		end

		def dump_to_file(file)
			classifier_snapshot = Marshal.dump @classifier
			File.open(file, "w") {|f| f.write(classifier_snapshot) }
		end

  end
end