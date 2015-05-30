#!/usr/bin/env ruby

require 'rubygems'
require 'hpricot'
require 'open-uri'
require 'pry'
require "rss"
require 'time'

class AlreadySeenException < Exception
end

def getFileUrl(js)
  js.split("\n").each do |line|
    match = /_stwVar\['fileurl'\]= '(.*)';/.match(line)
    return match[1] if match
  end
end

def getSTWMetadata(media_id)
  stw_url = "http://dmanager.streamtheworld.com/feed_xml/xmlLibrary2.php?requestinfo=1&client_id=1331&check=1Y3iTN8&mediaid=#{media_id}&list_library=1&list_playlists=0&list_categories=0&timestamp=1368042118344"
  doc = open(stw_url) { |f| Hpricot.XML(f) }
  file_tag = doc.at("file")
  {
    url: "http://wsbam.media.streamtheworld.com" + file_tag.inner_html,
    size: file_tag.attributes['file_size'],
    date: doc.at("item/date").inner_html
  }
end

def parseDate(link_text)
  matches = /(\d+)[\/\-](\d+)[\/\-](\d+)/.match(link_text)
  return nil if not matches
  month = matches[1].to_i
  day = matches[2].to_i
  year = ("20"+matches[3]).to_i
  Date.new(year, month, day).rfc2822
end

def getPodcastMetadata(link)
  url = link.attributes['href']
  puts url
  if url.start_with?('http://www.wsbradio.com/Player')
    media_id = url.split("/")[-1]
    data = getSTWMetadata(media_id)
    puts data
    return data
  elsif not url.end_with?('mp3')
    doc = open(url) { |f| Hpricot(f) }
    script = doc.search("script")[1].inner_html
    url = getFileUrl(script)
    puts url
  end
  puts link.inner_html
  date = parseDate(link.inner_html)
  puts date
	return {
		url: url,
		size: 30000000, # we no longer get a valid size
		date: date
	}
end

def getPodcastFiles(blogpage)
  puts blogpage
	page = open(blogpage) { |f| Hpricot(f) }
	podcasts = page.search("div.text a[text()*='Podcast']")
	if !podcasts.empty?
		return podcasts.map{|a| getPodcastMetadata(a)}.compact
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

populateSavedPodcasts("https://raw.githubusercontent.com/SnacksOnAPlane/agscraper/master/adamgoldfein.rss")

i=0
podcasts = []
loop do
	i+=1
	begin
		url = "http://adamgoldfein.com/category/blog/page/#{i}/"
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
