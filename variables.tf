# --- Secrets ---
variable "openai_api_key" {
  description = "OpenAI API Key"
  type        = string
  sensitive   = true
}

variable "pinecone_api_key" {
  description = "Pinecone API Key"
  type        = string
  sensitive   = true
}

# --- OpenAI Configuration ---
variable "openai_embedding_model" {
  description = "The name of the OpenAI embedding model."
  type        = string
  default     = "text-embedding-3-small"
}

variable "openai_chat_model" {
  description = "The name of the OpenAI chat model."
  type        = string
  default     = "gpt-4.1-mini-2025-04-14"
}

variable "openai_embedding_model_dimensions" {
  description = "The dimension size of the embedding model."
  type        = string
  default     = "768"
}

# --- Pinecone Configuration ---
variable "pinecone_environment" {
  description = "The Pinecone environment/region."
  type        = string
  default     = "us-east-1"
}

variable "pinecone_index_name" {
  description = "The name of the Pinecone index."
  type        = string
  default     = "basic-rag"
}

variable "pinecone_cloud_provider" {
  description = "The cloud provider for the Pinecone index."
  type        = string
  default     = "aws"
}