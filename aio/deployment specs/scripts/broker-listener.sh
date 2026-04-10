#!/bin/bash
az iot ops broker listener port add --service-type NodePort --port 1883 --listener external-broker-listener