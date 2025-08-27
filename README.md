# bench-event-systems-on-k8s
Benchmark of event messaging systems on Kubernetes.

## Overview

This repository contains the resources used to benchmark Apache Kafka, Apache Pulsar, and NATS JetStream in an environment closely resembling a production setting. The goal is to evaluate their suitability for production deployments on Kubernetes.  This project presents the results of experimentation focused on deployment complexity, network isolation, high availability, and security for each system.

## Objectives

This benchmark aims to:

*   Assess the deployment complexity on Kubernetes.
*   Evaluate network isolation capabilities.
*   Confirm high availability and security features aligned with production requirements.
*   Provide quantifiable results (performance, stability, resource consumption).

## Target Deployment Architecture

The target deployment architecture for each solution adheres to the following requirements:

*   **High Availability:** Minimum of 2 instances, with a target of 3.
*   **Security:** Utilization of cert-manager for certificate generation and SSL encryption for data transmission.
*   **Storage:** Persistent data storage via Persistent Volumes.
*   **Deployment:** Preference for Kubernetes CRDs for resource deployment; Helm Charts as an alternative.
*   **Best Practices:** Adherence to official documentation recommendations for production environments.

## Benchmark Details

A custom benchmark was developed to compare the systems. It measures:

*   **Throughput:**  Incoming and outgoing data rates.
*   **Latency:**  Delay in message processing.

The benchmark is designed to be simple and straightforward to ensure fair and equitable comparisons between the systems.

## Contents

This repository includes:

*   Kubernetes manifests and configuration files for deploying each event messaging system.
*   The custom benchmark application and scripts.
*   Results and analysis of the benchmark experiments.

