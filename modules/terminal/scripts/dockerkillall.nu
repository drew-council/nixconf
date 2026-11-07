#!/usr/bin/env nu

docker ps --format "{{.ID}}" | lines | par-each {|id| docker kill $id }
