using System;

namespace WarehouseSystem;

public class ProductQuantity
{
    private int _quantity;

    public ProductQuantity(Product product, int quantity)
    {
        Product = product ?? throw new ArgumentNullException(nameof(product));
        if (quantity <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(quantity), "Quantity must be positive.");
        }

        Quantity = quantity;
    }

    public Product Product { get; }

    public int Quantity
    {
        get => _quantity;
        private set
        {
            if (value < 0)
            {
                throw new ArgumentOutOfRangeException(nameof(value), "Quantity cannot be negative.");
            }

            _quantity = value;
        }
    }

    public double TotalVolume => Product.UnitVolume * Quantity;

    public decimal TotalCost => Product.UnitPrice * Quantity;

    public void AddQuantity(int amount)
    {
        if (amount <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(amount), "Amount must be positive.");
        }

        Quantity += amount;
    }

    public bool TryRemoveQuantity(int amount)
    {
        if (amount <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(amount), "Amount must be positive.");
        }

        if (amount > _quantity)
        {
            return false;
        }

        Quantity -= amount;
        return true;
    }
}
