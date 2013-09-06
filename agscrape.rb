#!/usr/bin/env ruby

require 'rubygems'
require 'hpricot'
require 'open-uri'
require 'pry'
require "rss"

class AlreadySeenException < Exception
end

def getPodcastMetadata(wsblink)
	media_id = wsblink.split("/")[-1]
	stw_url = "http://dmanager.streamtheworld.com/feed_xml/xmlLibrary2.php?requestinfo=1&client_id=1331&check=1Y3iTN8&mediaid=#{media_id}&list_library=1&list_playlists=0&list_categories=0&timestamp=1368042118344"
	doc = open(stw_url) { |f| Hpricot.XML(f) }
	file_tag = doc.at("file")
	return {
		url: "http://wsbam.media.streamtheworld.com" + file_tag.inner_html,
		size: file_tag.attributes['file_size'],
		date: doc.at("item/date").inner_html
	}
end

def getPodcastFiles(link)
	page = open(link) { |f| Hpricot(f) }
	podcasts = page.search("a[text()*='Podcast -']")
	if !podcasts.empty?
		return podcasts.map{|a| getPodcastMetadata(a.attributes['href'])}
	end
	return []
end

def extractPodcast(article)
	main_link = article.at("a")
	title = main_link.attributes['title']
	link = main_link.attributes['href']
	files = getPodcastFiles(link)
	files.each do |f|
		if $podcastUrls.include?(f[:url])
			$consecutiveErrors += 1
			raise AlreadySeenException, f[:url]
		else
			$consecutiveErrors = 0
		end
	end
	description = article.at("p").inner_html
	return {
		title: title,
		description: description,
		files: files
	}
end

def extractPodcasts(page)
	articles = page/"article"
	retme = articles.map do |article|
		begin
			extractPodcast(article)
		rescue AlreadySeenException => e
			puts e.message
			if $consecutiveErrors > 5
				raise e
			end
		end
	end
	retme.reject { |article| article.nil? }
end

def populateSavedPodcasts(url)
	open(url) do |rss|
		feed = RSS::Parser.parse(rss)
		$savedPodcasts = feed.items
		$podcastUrls = Set.new(feed.items.map { |item| item.link })
	end
end

populateSavedPodcasts(ARGV[0])

i=0
podcasts = []
loop do
	i+=1
	begin
		url = "http://adamgoldfein.com/page/#{i}/"
		puts url
		doc = open(url) { |f| Hpricot(f) }
		podcasts.concat(extractPodcasts(doc))
	rescue AlreadySeenException => e
		break
	end
end

rss = RSS::Maker.make("2.0") do |maker|
	maker.channel.author = "Adam Goldfein"
	maker.channel.updated = Time.now.to_s
	maker.channel.about = "http://www.adamgoldfein.com"
	maker.channel.title = "Adam Goldfein"
	maker.channel.description = maker.channel.title
	maker.channel.link = maker.channel.about

	podcasts.each do |podcast|
		podcast[:files].each_with_index do |file, index|
			maker.items.new_item do |item|
				item.link = file[:url]
				item.title = podcast[:title] + " Hour #{index+1}"
				item.description = podcast[:description]
				item.itunes_summary = item.description
				item.updated = file[:date]
				item.guid.content = item.link
				item.guid.isPermaLink = true
				item.pubDate = file[:date]
				item.enclosure.url = item.link
				item.enclosure.length = file[:size]
				item.enclosure.type = 'audio/mpeg'
			end
		end
	end

	$savedPodcasts.each do |rssitem|
		maker.items.new_item do |item|
			item.link = rssitem.link
			item.title = rssitem.title
			item.description = rssitem.description
			item.itunes_summary = rssitem.itunes_summary
			item.guid.content = rssitem.link
			item.guid.isPermaLink = true
			item.pubDate = rssitem.pubDate
			item.enclosure.url = rssitem.link
			item.enclosure.length = rssitem.enclosure.length
			item.enclosure.type = 'audio/mpeg'
		end
	end
end

File.open("adamgoldfein.rss", "w") { |file| file.write(rss) }
