variable "aws_region" {
  default = "eu-west-1"
}

variable "project_name" {
  default = "uptime-monitor"
}

variable "alert_email" {
  description = "email notification"
  type        = string
  sensitive   = true
}

variable "websites_to_monitor" {
  description = "List of websites to monitor"
  type        = list(string)
  default = [
    "https://www.google.com",
    "https://github.com",
    "https://aws.amazon.com"
  ]
}

variable "response_time_threshold_ms" {
  description = "Alert if the response exeeds this time (milliseconds)"
  type        = number
  default     = 3000
}