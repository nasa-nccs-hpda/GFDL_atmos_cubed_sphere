#ifndef GPU_MEMORY_MANAGER_H
#define GPU_MEMORY_MANAGER_H

#include <string>
#include <unordered_map>
#include <memory>
#include <stdexcept>
#include <iostream>
#include <cuda_runtime.h>

namespace held_suarez {
namespace infrastructure {

/**
 * @brief GPU Memory Manager - Singleton for persistent GPU buffer management
 * 
 * This class manages persistent GPU buffers throughout the model lifetime,
 * avoiding repeated allocations and deallocations that can harm performance.
 * 
 * Features:
 * - Named buffer management
 * - Type-safe allocations
 * - Memory usage tracking
 * - Automatic cleanup
 * - Thread-safe (TODO: add mutex if needed for multi-GPU)
 */
class GPUMemoryManager {
public:
    /**
     * @brief Get singleton instance
     */
    static GPUMemoryManager& instance() {
        static GPUMemoryManager instance;
        return instance;
    }
    
    // Delete copy/move constructors
    GPUMemoryManager(const GPUMemoryManager&) = delete;
    GPUMemoryManager& operator=(const GPUMemoryManager&) = delete;
    GPUMemoryManager(GPUMemoryManager&&) = delete;
    GPUMemoryManager& operator=(GPUMemoryManager&&) = delete;
    
    /**
     * @brief Allocate a named GPU buffer
     * 
     * @tparam T Element type
     * @param name Unique buffer name
     * @param count Number of elements
     * @return Pointer to GPU memory
     * @throws std::runtime_error if allocation fails or name already exists
     */
    template<typename T>
    T* allocate(const std::string& name, size_t count) {
        if (count == 0) {
            throw std::runtime_error("Cannot allocate zero-size buffer");
        }
        
        // Check if buffer already exists
        if (buffers_.find(name) != buffers_.end()) {
            throw std::runtime_error("Buffer '" + name + "' already exists");
        }
        
        // Allocate GPU memory
        T* ptr = nullptr;
        size_t bytes = count * sizeof(T);
        cudaError_t err = cudaMalloc(&ptr, bytes);
        
        if (err != cudaSuccess) {
            throw std::runtime_error(
                "Failed to allocate GPU memory for '" + name + "': " +
                cudaGetErrorString(err)
            );
        }
        
        // Store buffer info
        BufferInfo info;
        info.ptr = reinterpret_cast<void*>(ptr);
        info.size = bytes;
        info.count = count;
        info.type_name = typeid(T).name();
        info.element_size = sizeof(T);
        
        buffers_[name] = info;
        total_allocated_ += bytes;
        if (total_allocated_ > peak_allocated_) {
            peak_allocated_ = total_allocated_;
        }
        
        if (verbose_) {
            std::cout << "[GPU Memory] Allocated '" << name << "': "
                      << bytes / (1024.0 * 1024.0) << " MB\n";
        }
        
        return ptr;
    }
    
    /**
     * @brief Get existing buffer
     * 
     * @tparam T Element type (must match allocation type)
     * @param name Buffer name
     * @return Pointer to GPU memory
     * @throws std::runtime_error if buffer doesn't exist or type mismatch
     */
    template<typename T>
    T* get(const std::string& name) {
        auto it = buffers_.find(name);
        if (it == buffers_.end()) {
            throw std::runtime_error("Buffer '" + name + "' not found");
        }
        
        // Type safety check
        if (it->second.type_name != typeid(T).name()) {
            throw std::runtime_error(
                "Type mismatch for buffer '" + name + "': expected " +
                it->second.type_name + ", got " + typeid(T).name()
            );
        }
        
        return reinterpret_cast<T*>(it->second.ptr);
    }
    
    /**
     * @brief Reallocate buffer if size changed
     * 
     * @tparam T Element type
     * @param name Buffer name
     * @param new_count New number of elements
     * @return Pointer to GPU memory (may be different from original)
     */
    template<typename T>
    T* reallocate(const std::string& name, size_t new_count) {
        auto it = buffers_.find(name);
        if (it == buffers_.end()) {
            // Buffer doesn't exist, just allocate
            return allocate<T>(name, new_count);
        }
        
        // Check if size actually changed
        size_t new_bytes = new_count * sizeof(T);
        if (it->second.size == new_bytes) {
            return get<T>(name);
        }
        
        // Free old buffer
        free(name);
        
        // Allocate new buffer
        return allocate<T>(name, new_count);
    }
    
    /**
     * @brief Free a specific buffer
     * 
     * @param name Buffer name
     */
    void free(const std::string& name) {
        auto it = buffers_.find(name);
        if (it == buffers_.end()) {
            return;  // Already freed or never existed
        }
        
        cudaError_t err = cudaFree(it->second.ptr);
        if (err != cudaSuccess && verbose_) {
            std::cerr << "[GPU Memory] Warning: Failed to free '" << name << "': "
                      << cudaGetErrorString(err) << "\n";
        }
        
        total_allocated_ -= it->second.size;
        
        if (verbose_) {
            std::cout << "[GPU Memory] Freed '" << name << "': "
                      << it->second.size / (1024.0 * 1024.0) << " MB\n";
        }
        
        buffers_.erase(it);
    }
    
    /**
     * @brief Free all buffers
     */
    void reset() {
        for (auto& pair : buffers_) {
            cudaFree(pair.second.ptr);
        }
        buffers_.clear();
        total_allocated_ = 0;
        
        if (verbose_) {
            std::cout << "[GPU Memory] All buffers freed\n";
        }
    }
    
    /**
     * @brief Check if buffer exists
     */
    bool exists(const std::string& name) const {
        return buffers_.find(name) != buffers_.end();
    }
    
    /**
     * @brief Get buffer size in bytes
     */
    size_t get_size(const std::string& name) const {
        auto it = buffers_.find(name);
        if (it == buffers_.end()) {
            return 0;
        }
        return it->second.size;
    }
    
    /**
     * @brief Get buffer element count
     */
    size_t get_count(const std::string& name) const {
        auto it = buffers_.find(name);
        if (it == buffers_.end()) {
            return 0;
        }
        return it->second.count;
    }
    
    /**
     * @brief Total currently allocated memory
     */
    size_t total_allocated() const { return total_allocated_; }
    
    /**
     * @brief Peak allocated memory
     */
    size_t peak_allocated() const { return peak_allocated_; }
    
    /**
     * @brief Number of buffers
     */
    size_t buffer_count() const { return buffers_.size(); }
    
    /**
     * @brief Enable/disable verbose logging
     */
    void set_verbose(bool verbose) { verbose_ = verbose; }
    
    /**
     * @brief Print memory summary
     */
    void print_summary(std::ostream& os = std::cout) const {
        os << "\n=== GPU Memory Summary ===\n";
        os << "Total allocated: " << total_allocated_ / (1024.0 * 1024.0) << " MB\n";
        os << "Peak allocated:  " << peak_allocated_ / (1024.0 * 1024.0) << " MB\n";
        os << "Buffer count:    " << buffers_.size() << "\n";
        os << "\nBuffers:\n";
        
        for (const auto& pair : buffers_) {
            os << "  " << pair.first << ": "
               << pair.second.size / (1024.0 * 1024.0) << " MB "
               << "(" << pair.second.count << " elements of "
               << pair.second.element_size << " bytes)\n";
        }
        os << "==========================\n\n";
    }
    
private:
    GPUMemoryManager() 
        : total_allocated_(0), peak_allocated_(0), verbose_(false) {}
    
    ~GPUMemoryManager() {
        if (verbose_ && !buffers_.empty()) {
            std::cout << "[GPU Memory] Cleaning up " << buffers_.size() 
                      << " remaining buffers\n";
        }
        reset();
    }
    
    struct BufferInfo {
        void* ptr;                // GPU pointer
        size_t size;              // Size in bytes
        size_t count;             // Number of elements
        std::string type_name;    // Type name for safety
        size_t element_size;      // Bytes per element
    };
    
    std::unordered_map<std::string, BufferInfo> buffers_;
    size_t total_allocated_;
    size_t peak_allocated_;
    bool verbose_;
};

/**
 * @brief RAII wrapper for GPU buffer
 * 
 * Automatically frees buffer when going out of scope
 */
template<typename T>
class GPUBuffer {
public:
    GPUBuffer(const std::string& name, size_t count)
        : name_(name), ptr_(nullptr) {
        auto& mgr = GPUMemoryManager::instance();
        ptr_ = mgr.allocate<T>(name, count);
    }
    
    ~GPUBuffer() {
        if (!name_.empty()) {
            auto& mgr = GPUMemoryManager::instance();
            mgr.free(name_);
        }
    }
    
    // Disable copy
    GPUBuffer(const GPUBuffer&) = delete;
    GPUBuffer& operator=(const GPUBuffer&) = delete;
    
    // Enable move
    GPUBuffer(GPUBuffer&& other) noexcept
        : name_(std::move(other.name_)), ptr_(other.ptr_) {
        other.ptr_ = nullptr;
        other.name_.clear();
    }
    
    GPUBuffer& operator=(GPUBuffer&& other) noexcept {
        if (this != &other) {
            if (!name_.empty()) {
                auto& mgr = GPUMemoryManager::instance();
                mgr.free(name_);
            }
            name_ = std::move(other.name_);
            ptr_ = other.ptr_;
            other.ptr_ = nullptr;
            other.name_.clear();
        }
        return *this;
    }
    
    T* get() { return ptr_; }
    const T* get() const { return ptr_; }
    
    operator T*() { return ptr_; }
    operator const T*() const { return ptr_; }
    
private:
    std::string name_;
    T* ptr_;
};

} // namespace infrastructure
} // namespace held_suarez

#endif // GPU_MEMORY_MANAGER_H