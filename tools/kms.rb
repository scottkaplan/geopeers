#!/usr/bin/ruby

require 'aws-sdk'

class Kms
  def initialize
    @kms = Aws::KMS::Client.new(region:'us-east-1')
    @keyid = '5b925820-c88c-4a28-a668-d4ad173aa3e8'
  end

  def encrypt(plaintext)
    begin
      resp = @kms.encrypt(key_id: @keyid,
                          plaintext: plaintext)
      ciphertext = Base64.strict_encode64(resp.ciphertext_blob)
      return nil, ciphertext
    rescue Exception => e
      return e.to_json, nil
    end
  end

  def decrypt(ciphertext)
    begin
      cipher = Base64.strict_decode64(ciphertext)
      resp = @kms.decrypt(ciphertext_blob: cipher)
      return nil,resp.plaintext
    rescue Exception => e
      return e.to_json, nil
    end
  end
end

cipher_connection = Kms.new
err, ciphertext = cipher_connection.encrypt("Hello World")
if err
  puts "Error encrypting: #{err}"
  exit
end

puts ciphertext

err, plaintext = cipher_connection.decrypt(ciphertext)
if err
  puts "Error decrypting: #{err}"
  exit
end
puts "Plaintext: #{plaintext}"
