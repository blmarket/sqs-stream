AWS = require 'aws-sdk'
async = require 'async'
stream = require 'stream'

class SQSReadable extends stream.Readable
  constructor: (options) ->
    {@url} = options
    @sqs = new AWS.SQS()
    @local_buffer = []
    @wait = 'strict'
    
    super { objectMode: true }

  strict: (messages, cb) ->
    toTask = (msg) =>
      return (cb) =>
        @sqs.deleteMessage {
          QueueUrl: @url
          ReceiptHandle: msg.ReceiptHandle
        }, cb

    async.parallel (toTask(msg) for msg in messages), cb

  optimistic: (messages, cb) ->
    for msg in messages
      @sqs.deleteMessage {
        QueueUrl: @url
        ReceiptHandle: msg.ReceiptHandle
      }, -> return

    setImmediate cb

  _read: (size) ->
    while(@local_buffer.length > 0)
      item = @local_buffer.shift()
      return unless @push(item)

    @sqs.receiveMessage {
      QueueUrl: @url
      MaxNumberOfMessages: 10
      # WaitTimeSeconds: 10
      # VisibilityTimeout: 30
      AttributeNames: [ 'All' ]
    }, (err, resp) =>
      return @push(null) if err?
      return @push(null) unless resp.Messages?
      return @push(null) if resp.Messages.length == 0

      @local_buffer.push msg.Body for msg in resp.Messages

      switch @wait
        when 'strict' then @strict resp.Messages, =>
          @_read()
        when 'optimistic' then @optimistic resp.Messages, =>
          @_read()
        else throw new Error('wait method should be strict or optimistic')
      return
    return

setConfig = (config) ->
  AWS.config.update(config)
  return

createReadStream = (options) -> new SQSReadable(options)

# exported methods
module.exports.setConfig = setConfig
module.exports.createReadStream = createReadStream
