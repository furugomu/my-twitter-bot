{parseString} = require 'xml2js'
request = require 'request'
mongoose = require 'mongoose'
util = require 'util'

twitter = new require('ntwitter')
  consumer_key: process.env['TWITTER_CONSUMER_KEY']
  consumer_secret: process.env['TWITTER_CONSUMER_SECRET']
  access_token_key: process.env['TWITTER_ACCESS_TOKEN']
  access_token_secret: process.env['TWITTER_ACCESS_TOKEN_SECRET']

mongoose.connect process.env['MONGODB_URL'], (err) ->
  if err
    console.error(err)
    process.exit()

Item = mongoose.model 'Item',
  title: String
  description: String
  link: { type: String, unique: true }
  pubDate: Date
  checked: { type: Boolean, "default": false }

checkAzusa = ->
  url = 'http://feedblog.ameba.jp/rss/ameblo/azusa-tadokoro/rss20.xml'
  storeRssToMongo url, (err, item) ->
    if err
      console.error(err)
      return
    return if item.checked
    item.update checked: true, (err) ->
      console.error(err) if err
    notifyNewItem(item)

notifyNewItem = (item) ->
  desc = item.description.replace(/<[^>]+>/, '').replace(/\s+/, ' ').substring(0, 40)
  text = "@furugomu #{item.title} #{desc}... #{item.link}"
  console.log(text)
  twitter.updateStatus text, (err) ->
    console.error(err) if err

# If-Modified-Since つきでリクエストする
requestIfModified = (url, cb) ->
  lastModified = null
  headers = {}
  headers['Last-Modified'] = lastModified if lastModified
  request
    url: url
    headers: headers
  , (err, res, body) ->
    return cb(err) if err
    if res.headers.last_modified
      lastModified = res.headers.last_modified
    if res.statusCode != 304
      cb(err, res, body)

# XML を取ってきて JS オブジェクトにする
fetchXml = (url, cb) ->
  requestIfModified url, (err, res, body) ->
    return cb(err) if err
    parseString body, trim: true, explicitArray: false, (err, doc) ->
      return cb(err) if err
      cb(null, doc)

# RSS を取ってきて mongodb に入れる
# cb は mongo の document を引数に複数回呼ばれる
storeRssToMongo = (url, cb) ->
  fetchXml url, (err, doc) ->
    return cb(err) if err
    doc.rss.channel.item.forEach (values) ->
      return if values.link.match(/rssad/)
      # mongo に無ければ追加
      Item.findOne link: values.link, (err, item) ->
        return cb(err) if err
        return cb(null, item) if item
        Item.create values, (err, item) ->
          return cb(err) if err
          cb(null, item)

(->
  checkAzusa()
  setInterval checkAzusa, 7 * 60 * 1000
)()